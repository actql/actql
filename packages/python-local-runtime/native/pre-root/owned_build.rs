//! Build-only link to the one separately produced, source-qualified provider.
//! The ordinary producer must verify its exact bytes before/after Cargo and
//! package that same artifact next to this cdylib. No provider is compiled here.

use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=ACTQL_OWNED_PROVIDER_DIR");
    if env::var_os("CARGO_FEATURE_ACTQL_OWNED_CAPACITY").is_none() {
        return;
    }
    assert_eq!(env::var("CARGO_CFG_TARGET_OS").as_deref(), Ok("macos"));
    assert_eq!(env::var("CARGO_CFG_TARGET_ARCH").as_deref(), Ok("aarch64"));
    let selected = PathBuf::from(
        env::var_os("ACTQL_OWNED_PROVIDER_DIR").expect("missing original native provider artifact"),
    );
    assert!(selected.is_absolute(), "provider directory must be absolute");
    let text = selected.to_str().expect("provider directory must be UTF-8");
    assert!(!text.contains(['\r', '\n']), "invalid provider directive path");
    let directory = fs::symlink_metadata(&selected).expect("missing provider directory");
    assert!(directory.is_dir() && !directory.file_type().is_symlink());
    let provider = selected.join("libactql_native_control.dylib");
    let file = fs::symlink_metadata(&provider).expect("missing original native provider");
    assert!(file.is_file() && !file.file_type().is_symlink() && file.len() != 0);
    println!("cargo:rerun-if-changed={}", provider.display());
    println!("cargo:rustc-link-search=native={}", selected.display());
    // owned_abi.rs declares the exact dynamic dependency. Keep resolution local
    // to the packaged cohort, never PATH/DYLD/Homebrew or another provider copy.
    println!("cargo:rustc-link-arg=-Wl,-rpath,@loader_path");
    // Cargo's output directory is not an installed library identity. Match the
    // existing private Python binding layout, including after wheel relocation.
    println!("cargo:rustc-link-arg-cdylib=-Wl,-install_name,@rpath/_libwasmtime.dylib");
}
