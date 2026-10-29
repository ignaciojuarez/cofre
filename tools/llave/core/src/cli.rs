use clap::{Parser, Subcommand};
use std::path::PathBuf;
#[derive(Parser, Debug)]
#[command(name="llave-pair")]
pub struct Cli { #[arg(long, global=true)] pub simulate: bool, #[command(subcommand)] pub command: Commands }
#[derive(Subcommand, Debug)]
pub enum Commands {
 Devices { #[arg(long)] simulate: bool },
 Pair { #[arg(long)] udid: Option<String>, #[arg(long)] out: PathBuf, #[arg(long)] place: bool, #[arg(long)] simulate: bool },
}
