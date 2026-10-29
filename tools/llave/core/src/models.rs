use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct DeviceEntry {
    pub udid: String,
    pub name: String,
    pub version: String,
    pub connection_type: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum PairEvent {
    WaitingForUnlock,
    WaitingForTrust,
    Paired,
    WifiEnabled,
    Validated,
    Warning { code: String, message: String },
    Error { code: String, message: String },
}

impl PairEvent {
    pub fn emit(&self) {
        if let Ok(line) = serde_json::to_string(self) {
            println!("{}", line);
        }
    }
}
