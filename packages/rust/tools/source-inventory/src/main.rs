//! Read source syntax; never import the embedded runtime or execute a program.
use anyhow::{Result, ensure};
use std::path::Path;

fn main() -> Result<()> {
    let arguments: Vec<_> = std::env::args_os().skip(1).collect();
    ensure!(arguments.len() == 2, "Usage: source-inventory <repository-root> <Cargo-library-entry>");
    let modules = actql_source_inventory::inventory(Path::new(&arguments[0]), Path::new(&arguments[1]))?;
    println!("{}", serde_json::json!({
        "qualification": "rust-source-syntax-only; not compiler, ABI or runtime acceptance",
        "modules": modules,
    }));
    Ok(())
}
