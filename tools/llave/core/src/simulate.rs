use std::fs::File;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use tokio::time::{Duration, sleep};

use crate::models::{DeviceEntry, PairEvent};

pub fn simulated_devices() -> Vec<DeviceEntry> {
    vec![DeviceEntry {
        udid: "00008150-SIMULATED-DEV".to_string(),
        name: "Simulated iPhone".to_string(),
        version: "18.1".to_string(),
        connection_type: "USB".to_string(),
    }]
}

pub async fn run_simulated_pair(out_path: &Path) -> Result<(), String> {
    sleep(Duration::from_millis(250)).await;
    PairEvent::WaitingForUnlock.emit();

    sleep(Duration::from_millis(250)).await;
    PairEvent::WaitingForTrust.emit();

    sleep(Duration::from_millis(250)).await;
    PairEvent::Paired.emit();

    sleep(Duration::from_millis(250)).await;
    PairEvent::WifiEnabled.emit();

    sleep(Duration::from_millis(250)).await;
    PairEvent::Validated.emit();

    write_simulated_pairing_file(out_path)
}

pub fn write_simulated_pairing_file(out_path: &Path) -> Result<(), String> {
    let dummy_cert =
        b"-----BEGIN CERTIFICATE-----\nMIIBCgKCAQEA0simulatedcert...\n-----END CERTIFICATE-----"
            .to_vec();
    let dummy_key =
        b"-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFA...\n-----END PRIVATE KEY-----"
            .to_vec();
    let dummy_bytes_32 = vec![42u8; 32];

    let mut dict = plist::Dictionary::new();
    dict.insert(
        "DeviceCertificate".into(),
        plist::Value::Data(dummy_cert.clone()),
    );
    dict.insert(
        "HostCertificate".into(),
        plist::Value::Data(dummy_cert.clone()),
    );
    dict.insert(
        "HostPrivateKey".into(),
        plist::Value::Data(dummy_key.clone()),
    );
    dict.insert("RootCertificate".into(), plist::Value::Data(dummy_cert));
    dict.insert("RootPrivateKey".into(), plist::Value::Data(dummy_key));
    dict.insert(
        "SystemBUID".into(),
        plist::Value::String("SIMULATED-BUID-1234-5678".into()),
    );
    dict.insert(
        "HostID".into(),
        plist::Value::String("SIMULATED-HOST-1234-5678".into()),
    );
    dict.insert(
        "WiFiMACAddress".into(),
        plist::Value::String("00:11:22:33:44:55".into()),
    );
    dict.insert(
        "UDID".into(),
        plist::Value::String("00008150-SIMULATED-DEV".into()),
    );
    dict.insert("EscrowBag".into(), plist::Value::Data(vec![0xAA; 64]));

    // RemotePairing keys (iOS 17.4+)
    dict.insert(
        "public_key".into(),
        plist::Value::Data(dummy_bytes_32.clone()),
    );
    dict.insert("private_key".into(), plist::Value::Data(dummy_bytes_32));
    dict.insert(
        "identifier".into(),
        plist::Value::String("simulated-identifier-1234".into()),
    );

    let mut xml_bytes = Vec::new();
    plist::Value::Dictionary(dict)
        .to_writer_xml(&mut xml_bytes)
        .map_err(|e| format!("Failed to serialize simulated plist: {e}"))?;

    if let Some(parent) = out_path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("Failed to create parent dir: {e}"))?;
    }

    let mut file =
        File::create(out_path).map_err(|e| format!("Failed to create output file: {e}"))?;
    let mut perms = file.metadata().map_err(|e| e.to_string())?.permissions();
    perms.set_mode(0o600);
    file.set_permissions(perms).map_err(|e| e.to_string())?;

    file.write_all(&xml_bytes)
        .map_err(|e| format!("Failed to write pairing file: {e}"))?;
    file.flush()
        .map_err(|e| format!("Failed to flush pairing file: {e}"))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn simulated_file_has_pairing_keys_and_private_mode() {
        let p = std::env::temp_dir().join(format!("llave-test-{}.plist", std::process::id()));
        write_simulated_pairing_file(&p).unwrap();
        let value = plist::Value::from_file(&p).unwrap();
        let d = value.as_dictionary().unwrap();
        for key in [
            "HostID",
            "SystemBUID",
            "HostCertificate",
            "HostPrivateKey",
            "RootCertificate",
        ] {
            assert!(d.contains_key(key), "missing {key}");
        }
        assert_eq!(
            std::fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let _ = std::fs::remove_file(p);
    }
}
