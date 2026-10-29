use idevice::{
    IdeviceService,
    lockdown::LockdownClient,
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection},
};

use crate::models::DeviceEntry;

pub async fn list_devices() -> Result<Vec<DeviceEntry>, String> {
    let mut usbmuxd = match UsbmuxdConnection::default().await {
        Ok(conn) => conn,
        Err(e) => {
            // If usbmuxd daemon is unreachable or returns error, treat as no devices
            eprintln!("[llave] usbmuxd connection notice: {e}");
            return Ok(vec![]);
        }
    };

    let devs = match usbmuxd.get_devices().await {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[llave] get_devices notice: {e}");
            return Ok(vec![]);
        }
    };

    if devs.is_empty() {
        return Ok(vec![]);
    }

    let usbmuxd_addr = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let mut entries = Vec::new();

    for d in devs {
        let connection_type = match d.connection_type {
            Connection::Usb => "USB",
            Connection::Network(_) => "Network",
            Connection::Unknown(_) => "Unknown",
        }
        .to_string();

        let provider = d.to_provider(usbmuxd_addr.clone(), "llave");
        let (name, version) = match LockdownClient::connect(&provider).await {
            Ok(mut lc) => {
                let dev_name = lc
                    .get_value(Some("DeviceName"), None)
                    .await
                    .ok()
                    .and_then(|v| v.as_string().map(|s| s.to_string()))
                    .unwrap_or_else(|| "iPhone".to_string());
                let prod_ver = lc
                    .get_value(Some("ProductVersion"), None)
                    .await
                    .ok()
                    .and_then(|v| v.as_string().map(|s| s.to_string()))
                    .unwrap_or_else(|| "Unknown".to_string());
                (dev_name, prod_ver)
            }
            Err(_) => ("iPhone".to_string(), "Unknown".to_string()),
        };

        entries.push(DeviceEntry {
            udid: d.udid,
            name,
            version,
            connection_type,
        });
    }

    Ok(entries)
}
