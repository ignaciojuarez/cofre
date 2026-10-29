use std::fs::File;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use tokio::time::{sleep, Duration};

use idevice::{
    IdeviceError, IdeviceService,
    lockdown::LockdownClient,
    remote_pairing::{RemotePairingLockdownService, RpPairingFile},
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection},
};

use crate::models::PairEvent;

const PROHIBITED_IPAD_UDID: &str = "COFRE_DEVICE_UDID";

pub async fn run_pair(udid_opt: Option<String>, out_path: &Path, place: bool) -> Result<(), String> {
    let mut usbmuxd = UsbmuxdConnection::default()
        .await
        .map_err(|e| format!("Failed to connect to usbmuxd: {e}"))?;

    let devs = usbmuxd
        .get_devices()
        .await
        .map_err(|e| format!("Failed to list devices: {e}"))?;

    let dev = match udid_opt {
        Some(target_udid) => {
            devs.into_iter()
                .find(|d| d.udid.eq_ignore_ascii_case(&target_udid))
                .ok_or_else(|| format!("Device with UDID {target_udid} not found"))?
        }
        None => {
            let usb_devs: Vec<_> = devs
                .into_iter()
                .filter(|d| d.connection_type == Connection::Usb)
                .collect();
            if usb_devs.is_empty() {
                return Err("No device connected via USB".to_string());
            } else if usb_devs.len() > 1 {
                return Err("Multiple USB devices found. Please specify --udid".to_string());
            }
            usb_devs.into_iter().next().unwrap()
        }
    };

    if dev.udid.eq_ignore_ascii_case(PROHIBITED_IPAD_UDID) {
        let err = PairEvent::Error {
            code: "DEVICE_RESTRICTED".to_string(),
            message: "Pairing with iPad mini is prohibited".to_string(),
        };
        err.emit();
        return Err("Pairing with iPad mini is prohibited".to_string());
    }

    let usbmuxd_addr = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let provider = dev.to_provider(usbmuxd_addr, "llave");

    let mut lc = LockdownClient::connect(&provider)
        .await
        .map_err(|e| format!("Failed to connect to lockdown service: {e}"))?;

    let prod_version = lc
        .get_value(Some("ProductVersion"), None)
        .await
        .ok()
        .and_then(|v| v.as_string().map(|s| s.to_string()))
        .unwrap_or_else(|| "17.4".to_string());

    let buid = usbmuxd
        .get_buid()
        .await
        .unwrap_or_else(|_| uuid::Uuid::new_v4().to_string().to_uppercase());

    let host_id = uuid::Uuid::new_v4().to_string().to_uppercase();

    // Loop for unlock & trust
    let mut emitted_unlock = false;
    let mut emitted_trust = false;
    let pairing_file = loop {
        match lc.pair_once(&host_id, &buid, Some("Llave")).await {
            Ok(pf) => {
                PairEvent::Paired.emit();
                break pf;
            }
            Err(IdeviceError::PasswordProtected) => {
                if !emitted_unlock {
                    PairEvent::WaitingForUnlock.emit();
                    emitted_unlock = true;
                }
                sleep(Duration::from_millis(1000)).await;
            }
            Err(IdeviceError::PairingDialogResponsePending) => {
                if !emitted_trust {
                    PairEvent::WaitingForTrust.emit();
                    emitted_trust = true;
                }
                sleep(Duration::from_millis(1000)).await;
            }
            Err(IdeviceError::UserDeniedPairing) => {
                let err = PairEvent::Error {
                    code: "USER_DENIED".to_string(),
                    message: "User rejected trust prompt on device".to_string(),
                };
                err.emit();
                return Err("User rejected trust prompt".to_string());
            }
            Err(e) => {
                // Check if device is already paired
                if let Ok(existing_record) = usbmuxd.get_pair_record(&dev.udid).await {
                    if lc.start_session(&existing_record).await.is_ok() {
                        PairEvent::Paired.emit();
                        break existing_record;
                    }
                }
                let err = PairEvent::Error {
                    code: "PAIRING_FAILED".to_string(),
                    message: format!("Pairing failed: {e}"),
                };
                err.emit();
                return Err(format!("Pairing error: {e}"));
            }
        }
    };

    // Note: WE DO NOT CALL usbmuxd.save_pair_record!
    // This strictly ensures no /var/db/lockdown file or keychain record is persisted on the Mac.

    // Start session to test pairing record
    lc.start_session(&pairing_file)
        .await
        .map_err(|e| format!("Failed to validate lockdown session: {e}"))?;

    // Enable wireless lockdown connections
    let _ = lc
        .set_value(
            "EnableWifiConnections",
            true.into(),
            Some("com.apple.mobile.wireless_lockdown"),
        )
        .await;

    let _ = lc
        .set_value(
            "EnableWifiDebugging",
            true.into(),
            Some("com.apple.mobile.wireless_lockdown"),
        )
        .await;

    PairEvent::WifiEnabled.emit();

    // Prepare combined plist
    let mut pairing_file_with_udid = pairing_file;
    pairing_file_with_udid.udid = Some(dev.udid.clone());
    let serialized_lockdown = pairing_file_with_udid
        .serialize()
        .map_err(|e| format!("Failed to serialize lockdown record: {e}"))?;

    let lockdown_val: plist::Value = plist::Value::from_reader_xml(std::io::Cursor::new(&serialized_lockdown))
        .map_err(|e| format!("Failed to parse lockdown plist: {e}"))?;

    let mut combined_dict = match lockdown_val {
        plist::Value::Dictionary(d) => d,
        _ => return Err("Lockdown record is not a dictionary".to_string()),
    };

    // RemotePairing for iOS 17.4+
    if !is_ios_version_below(&prod_version, 17, 4) {
        let hostname = format!("llave-{}", &uuid::Uuid::new_v4().simple().to_string()[..6]);
        if let Ok(service) = RemotePairingLockdownService::connect(&provider).await {
            if let Ok(mut rp_client) = service.into_client(&hostname) {
                let mut rp_file = RpPairingFile::generate(&hostname);
                if rp_client.connect(&mut rp_file, async || "000000".to_string()).await.is_ok() {
                    let rp_bytes = rp_file.to_bytes();
                    if let Ok(plist::Value::Dictionary(rp_dict)) =
                        plist::Value::from_reader_xml(std::io::Cursor::new(&rp_bytes))
                    {
                        for (k, v) in rp_dict {
                            combined_dict.insert(k, v);
                        }
                    }
                }
            }
        }
    }

    // Validation
    let required_lockdown_keys = [
        "DeviceCertificate",
        "HostCertificate",
        "HostPrivateKey",
        "RootCertificate",
        "RootPrivateKey",
        "SystemBUID",
        "HostID",
        "WiFiMACAddress",
    ];

    for key in required_lockdown_keys {
        if !combined_dict.contains_key(key) {
            let err = PairEvent::Error {
                code: "VALIDATION_FAILED".to_string(),
                message: format!("Missing required key: {key}"),
            };
            err.emit();
            return Err(format!("Validation missing {key}"));
        }
    }

    PairEvent::Validated.emit();

    // Write file with 0600 permissions
    let mut xml_bytes = Vec::new();
    plist::Value::Dictionary(combined_dict)
        .to_writer_xml(&mut xml_bytes)
        .map_err(|e| format!("Failed to serialize combined plist: {e}"))?;

    if place {
        let house = idevice::house_arrest::HouseArrestClient::connect(&provider).await.map_err(|e| format!("Cofre is not installed or house_arrest is unavailable: {e}"))?;
        let mut afc = match house.vend_container("com.ignaciojuarez.cofre").await { Ok(a) => a, Err(_) => idevice::house_arrest::HouseArrestClient::connect(&provider).await.map_err(|e| format!("Cofre placement failed: {e}"))?.vend_documents("com.ignaciojuarez.cofre").await.map_err(|e| format!("Cofre placement failed: {e}"))? };
        let _ = afc.mk_dir("/Documents/StikJIT").await;
        let mut f = afc.open("/Documents/StikJIT/pairingFile.plist", idevice::afc::opcode::AfcFopenMode::Wr).await.map_err(|e| format!("Cofre placement failed: {e}"))?;
        f.write_entire(&xml_bytes).await.map_err(|e| format!("Cofre placement failed: {e}"))?;
        f.close().await.map_err(|e| format!("Cofre placement failed: {e}"))?;
        println!("{{\"event\":\"placed\"}}");
    }

    if let Some(parent) = out_path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("Failed to create parent dir: {e}"))?;
    }

    let mut file = File::create(out_path).map_err(|e| format!("Failed to create output file: {e}"))?;
    let mut perms = file.metadata().map_err(|e| e.to_string())?.permissions();
    perms.set_mode(0o600);
    file.set_permissions(perms).map_err(|e| e.to_string())?;

    file.write_all(&xml_bytes).map_err(|e| format!("Failed to write pairing file: {e}"))?;
    file.flush().map_err(|e| format!("Failed to flush pairing file: {e}"))?;

    Ok(())
}

fn is_ios_version_below(version: &str, target_major: u32, target_minor: u32) -> bool {
    let mut parts = version.split('.');
    let major = parts
        .next()
        .and_then(|s| s.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse::<u32>().ok())
        .unwrap_or(0);
    let minor = parts
        .next()
        .and_then(|s| s.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse::<u32>().ok())
        .unwrap_or(0);
    (major, minor) < (target_major, target_minor)
}
