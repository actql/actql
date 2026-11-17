//! Private generated-scalar admission. No Client operation is issued here.
#![allow(dead_code)]

use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, sync::Arc};
use wasmtime::{Engine, ExternType, FuncType, Instance, Linker, Memory, Module, Store, ValType};
use crate::abi_generated::{ABI_VERSION, CoreExports, EXPORTS, IMPORTS, Imports, link_imports};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Scalar { I32, I64 }

pub(crate) struct Signature {
    pub name: &'static str,
    pub parameters: &'static [Scalar],
    pub result: Scalar,
}

pub(crate) struct StoreState<H> {
    pub(crate) admitted: bool,
    pub(crate) host: H,
}

pub(crate) struct CoreInstance<H: 'static> {
    pub(crate) store: Store<StoreState<H>>,
    pub(crate) functions: CoreExports,
    pub(crate) memory: Memory,
    pub(crate) identity: Arc<()>,
}

// Compiled code can be reused without sharing a Store, callback owner, nonce or
// guest memory. Each instance still performs its own fenced ABI admission.
pub(crate) struct CompiledCore {
    engine: Engine,
    module: Module,
    initialization_fuel: u64,
}

// The containing runtime artifact selects this profile. It does not grant a
// Request or reserve the physical capacity owned by the embedding Host.
pub(crate) struct ArtifactProfile {
    pub(crate) sha256: [u8; 32],
    pub(crate) max_module_bytes: usize,
    pub(crate) memory_max_pages: u64,
    pub(crate) initialization_fuel: u64,
}

fn scalar(value: ValType) -> Option<Scalar> {
    match value { ValType::I32 => Some(Scalar::I32), ValType::I64 => Some(Scalar::I64), _ => None }
}

fn matches_signature(actual: &FuncType, expected: &Signature) -> bool {
    actual.params().map(scalar).eq(expected.parameters.iter().copied().map(Some)) &&
        actual.results().map(scalar).eq([Some(expected.result)])
}

fn validate_module(module: &Module, profile: &ArtifactProfile) -> wasmtime::Result<()> {
    let mut found = BTreeSet::new();
    for import in module.imports() {
        let expected = IMPORTS.iter().find(|value| value.name == import.name());
        let valid = match (import.ty(), expected) {
            (ExternType::Func(actual), Some(expected)) => matches_signature(&actual, expected),
            _ => false,
        };
        anyhow::ensure!(import.module() == "actql_host" && valid && found.insert(import.name().to_owned()),
                          "Unrecognized Core import: {}.{}", import.module(), import.name());
    }
    anyhow::ensure!(found.len() == IMPORTS.len(), "Missing Core import");
    // resources_required counts defined memories only. The closed imports
    // above reject imported memories, so this also fixes the total count.
    anyhow::ensure!(module.resources_required().num_memories == 1,
                    "Core memory count must be exactly one");
    found.clear();
    let mut memory_found = false;
    for export in module.exports() {
        if export.name() == "memory" {
            let ExternType::Memory(memory) = export.ty() else { anyhow::bail!("Invalid Core memory"); };
            anyhow::ensure!(!memory_found && !memory.is_64() && !memory.is_shared() &&
                memory.page_size_log2() == 16 && memory.maximum() == Some(profile.memory_max_pages) &&
                memory.minimum() <= profile.memory_max_pages, "Unbounded or incompatible Core memory");
            memory_found = true;
        } else {
            let expected = EXPORTS.iter().find(|value| value.name == export.name());
            let valid = match (export.ty(), expected) {
                (ExternType::Func(actual), Some(expected)) => matches_signature(&actual, expected),
                _ => false,
            };
            anyhow::ensure!(valid && found.insert(export.name().to_owned()), "Unrecognized Core export: {}", export.name());
        }
    }
    anyhow::ensure!(memory_found && found.len() == EXPORTS.len(), "Missing Core export or memory");
    Ok(())
}

// A failed constructor returns the SAME physical Host owner. Dropping the
// guest Store before admission is not an asynchronous Host cleanup receipt.
pub(crate) struct InitializationFailure<H> {
    pub(crate) cause: wasmtime::Error,
    pub(crate) host: H,
}

impl<H> std::fmt::Debug for InitializationFailure<H> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InitializationFailure").field("cause", &self.cause).finish_non_exhaustive()
    }
}

impl CompiledCore {
    pub(crate) fn compile(engine: &Engine, wasm: &[u8], profile: &ArtifactProfile)
        -> wasmtime::Result<Self> {
            anyhow::ensure!(!wasm.is_empty() && wasm.len() <= profile.max_module_bytes &&
                profile.initialization_fuel > 0 && profile.memory_max_pages > 0 &&
                profile.memory_max_pages <= 65536, "Invalid Core artifact profile");
            anyhow::ensure!(<[u8; 32]>::from(Sha256::digest(wasm)) == profile.sha256,
                            "Core artifact digest mismatch");
            let module = Module::new(engine, wasm)?;
            validate_module(&module, profile)?;
            Ok(Self { engine: engine.clone(), module,
                      initialization_fuel: profile.initialization_fuel })
    }

    pub(crate) fn instantiate<H: Imports>(&self, host: H)
        -> Result<CoreInstance<H>, InitializationFailure<H>> {
        let mut linker = Linker::new(&self.engine);
        match link_imports(&mut linker) {
            Ok(()) => (),
            Err(cause) => return Err(InitializationFailure { cause, host }),
        }
        // All callbacks remain closed through start functions, export binding
        // and the actual ABI version call. No physical Host callback has run if
        // this scope fails; the same Host can be returned to its original owner.
        let mut store = Store::new(&self.engine, StoreState { admitted: false, host });
        let initialized = (|| {
            store.set_fuel(self.initialization_fuel)?;
            let instance: Instance = linker.instantiate(&mut store, &self.module)?;
            let functions = CoreExports::load(instance, &mut store)?;
            let memory = instance.get_memory(&mut store, "memory")
                .ok_or_else(|| anyhow::anyhow!("Missing original Core memory"))?;
            anyhow::ensure!(functions.host_abi_version.call(&mut store, ())? == ABI_VERSION,
                            "Core ABI revision mismatch");
            Ok::<_, wasmtime::Error>((functions, memory))
        })();
        match initialized {
            Ok((functions, memory)) => {
                store.data_mut().admitted = true;
                Ok(CoreInstance { store, functions, memory, identity: Arc::new(()) })
            }
            Err(cause) => Err(InitializationFailure { cause, host: store.into_data().host }),
        }
    }
}

impl<H: Imports> CoreInstance<H> {
    pub(crate) fn open(engine: &Engine, wasm: &[u8], profile: &ArtifactProfile, host: H)
        -> Result<Self, InitializationFailure<H>> {
        match CompiledCore::compile(engine, wasm, profile) {
            Ok(compiled) => compiled.instantiate(host),
            Err(cause) => Err(InitializationFailure { cause, host }),
        }
    }
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::*;
    use std::sync::OnceLock;

    pub(crate) fn actual_module() -> &'static CompiledCore {
        static COMPILED: OnceLock<CompiledCore> = OnceLock::new();
        COMPILED.get_or_init(|| {
            let path = std::env::var_os("ACTQL_CORE_WASM")
                .expect("Select actual compiler-produced Core Wasm; no fixture fallback or skip");
            let wasm = std::fs::read(path).unwrap();
            let mut config = wasmtime::Config::new();
            config.consume_fuel(true);
            let engine = Engine::new(&config).unwrap();
            CompiledCore::compile(&engine, &wasm, &ArtifactProfile {
                sha256: Sha256::digest(&wasm).into(), max_module_bytes: 64 * 1024 * 1024,
                memory_max_pages: 256, initialization_fuel: 1_000_000_000,
            }).unwrap()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};
    use wasmtime::{Caller, Config};

    struct Observed(Arc<AtomicUsize>);
    impl Imports for Observed {
        fn input_byte(caller: Caller<'_, StoreState<Self>>, _: i32, _: i32) -> wasmtime::Result<i32> {
            caller.data().host.0.fetch_add(1, Ordering::SeqCst);
            Ok(0)
        }
    }

    fn engine() -> Engine {
        let mut config = Config::new(); config.consume_fuel(true);
        Engine::new(&config).unwrap()
    }

    fn profile(wasm: &[u8]) -> ArtifactProfile {
        ArtifactProfile { sha256: Sha256::digest(wasm).into(), max_module_bytes: 64*1024*1024,
            memory_max_pages: 256, initialization_fuel: 100_000_000 }
    }

    // A complete typed fixture is only a negative startup probe. The positive
    // Core acceptance below consumes the actual compiler-produced MoonBit Wasm.
    fn startup_fixture(start: bool, version: i32) -> Vec<u8> {
        module_fixture(start, version, false)
    }

    fn module_fixture(start: bool, version: i32, hidden_memory: bool) -> Vec<u8> {
        let mut wat = String::from("(module");
        for signature in IMPORTS {
            wat.push_str(&format!(" (import \"actql_host\" \"{}\" (func ${}", signature.name, signature.name));
            for scalar in signature.parameters { wat.push_str(match scalar { Scalar::I32 => " (param i32)", Scalar::I64 => " (param i64)" }); }
            wat.push_str(match signature.result { Scalar::I32 => " (result i32)))", Scalar::I64 => " (result i64)))" });
        }
        wat.push_str(" (memory (export \"memory\") 1 256)");
        if hidden_memory { wat.push_str(" (memory 1 256)"); }
        for signature in EXPORTS {
            wat.push_str(&format!(" (func (export \"{}\")",signature.name));
            for scalar in signature.parameters { wat.push_str(match scalar { Scalar::I32 => " (param i32)", Scalar::I64 => " (param i64)" }); }
            wat.push_str(match signature.result { Scalar::I32 => " (result i32)", Scalar::I64 => " (result i64)" });
            let value = if signature.name == "actql_host_abi_version" { version } else { 0 };
            wat.push_str(&format!(" ({}.const {}))", if signature.result == Scalar::I32 { "i32" } else { "i64" }, value));
        }
        if start { wat.push_str(" (func $start i32.const 1 i32.const 0 call $input_byte drop) (start $start)"); }
        wat.push(')');wat::parse_str(wat).unwrap()
    }

    #[test]
    fn startup_import_is_refused_before_any_physical_callback() {
        let wasm=startup_fixture(true, ABI_VERSION);let calls=Arc::new(AtomicUsize::new(0));
        let error=CoreInstance::open(&engine(),&wasm,&profile(&wasm),Observed(calls.clone())).err().unwrap();
        assert!(format!("{:#}",error.cause).contains("before Core admission"));
        assert_eq!(calls.load(Ordering::SeqCst),0);
    }

    #[test]
    fn wrong_revision_and_changed_digest_never_admit_callbacks() {
        let wasm=startup_fixture(false, ABI_VERSION+1);let calls=Arc::new(AtomicUsize::new(0));
        let error=CoreInstance::open(&engine(),&wasm,&profile(&wasm),Observed(calls.clone())).err().unwrap();
        assert!(error.cause.to_string().contains("ABI revision mismatch"));
        let mut invalid=profile(&wasm);invalid.sha256[0]^=1;
        let error=CoreInstance::open(&engine(),&wasm,&invalid,Observed(calls.clone())).err().unwrap();
        assert!(error.cause.to_string().contains("digest mismatch"));assert_eq!(calls.load(Ordering::SeqCst),0);
    }

    #[test]
    fn initialization_failure_retains_the_same_host_owner_before_and_after_store() {
        struct Kept(Arc<AtomicUsize>);
        impl Imports for Kept {}
        impl Drop for Kept {
            fn drop(&mut self) { self.0.fetch_add(1, Ordering::SeqCst); }
        }
        let wasm = startup_fixture(false, ABI_VERSION + 1);
        for invalid_digest in [true, false] {
            let original = Arc::new(AtomicUsize::new(0));
            let host = Kept(original.clone());
            let mut selected = profile(&wasm);
            if invalid_digest { selected.sha256[0] ^= 1; }
            let failure = CoreInstance::open(&engine(), &wasm, &selected, host).err().unwrap();
            assert_eq!(original.load(Ordering::SeqCst), 0);
            assert!(Arc::ptr_eq(&failure.host.0, &original));
            assert!(failure.cause.to_string().contains(if invalid_digest {
                "digest mismatch"
            } else { "ABI revision mismatch" }));
            drop(failure.host);
            assert_eq!(original.load(Ordering::SeqCst), 1);
        }
    }

    #[test]
    fn unexported_second_memory_is_refused_before_host_callbacks() {
        let wasm = module_fixture(false, ABI_VERSION, true);
        let mut config = Config::new();
        config.consume_fuel(true).wasm_multi_memory(true);
        let engine = Engine::new(&config).unwrap();
        let compiled = Module::new(&engine, &wasm).unwrap();
        assert_eq!(compiled.resources_required().num_memories, 2);
        let calls = Arc::new(AtomicUsize::new(0));
        let result = CoreInstance::open(&engine, &wasm, &profile(&wasm), Observed(calls.clone()));
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        let failure = result.err().expect("The unexported second memory must not be admitted");
        assert!(failure.cause.to_string().contains("Core memory count"));
        assert!(Arc::ptr_eq(&failure.host.0, &calls));
    }

    #[test]
    fn actual_core_module_binds_every_generated_signature() {
        let calls=Arc::new(AtomicUsize::new(0));
        let mut core=test_support::actual_module().instantiate(Observed(calls.clone())).unwrap();
        assert!(core.store.data().admitted);
        assert_eq!(core.functions.host_abi_version.call(&mut core.store,()).unwrap(),87);
        assert_eq!(calls.load(Ordering::SeqCst),0);
    }
}
