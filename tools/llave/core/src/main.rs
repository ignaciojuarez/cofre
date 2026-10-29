mod cli;
mod devices;
mod models;
mod pair;
mod simulate;

use clap::Parser;
use cli::{Cli, Commands};
use models::PairEvent;

#[tokio::main]
async fn main() {
    let args = Cli::parse();
    let global_simulate = args.simulate;

    match args.command {
        Commands::Devices { simulate } => {
            let is_sim = global_simulate || simulate;
            if is_sim {
                let devs = simulate::simulated_devices();
                println!("{}", serde_json::to_string(&devs).unwrap());
            } else {
                match devices::list_devices().await {
                    Ok(devs) => {
                        println!("{}", serde_json::to_string(&devs).unwrap());
                    }
                    Err(e) => {
                        eprintln!("[llave] Error listing devices: {e}");
                        println!("[]");
                    }
                }
            }
        }
        Commands::Pair { udid, out, place, simulate } => {
            let is_sim = global_simulate || simulate;
            if is_sim {
                if let Err(e) = simulate::run_simulated_pair(&out).await {
                    PairEvent::Error {
                        code: "SIMULATE_ERROR".to_string(),
                        message: e,
                    }
                    .emit();
                    std::process::exit(1);
                }
            } else {
                if let Err(e) = pair::run_pair(udid, &out, place).await {
                    eprintln!("[llave] Pair failed: {e}");
                    std::process::exit(1);
                }
            }
        }
    }
}
