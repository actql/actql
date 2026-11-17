//! Short, synchronous transfers through the existing Core buffer Owner.
#![allow(dead_code)]

use std::sync::Arc;
use crate::{abi::CoreInstance, abi_generated::Imports};

const BLOCK_BYTES: usize = 16_384;

// Numeric handles are private routing data. The original instance association
// is retained separately even if another instance has equal nonce/handle data.
pub(crate) struct InputBuffer {
    identity: Arc<()>,
    nonce: i64,
    pub(crate) handle: i32,
    bytes: usize,
    closed: bool,
}

#[derive(Debug)]
pub(crate) struct CoreFailure {
    pub(crate) operation: &'static str,
    pub(crate) code: i32,
}

impl std::fmt::Display for CoreFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} refused with original Core code {}", self.operation, self.code)
    }
}
impl std::error::Error for CoreFailure {}

fn success(operation: &'static str, code: i32) -> wasmtime::Result<()> {
    if code == 0 { Ok(()) } else { Err(CoreFailure { operation, code }.into()) }
}

impl<H: Imports> CoreInstance<H> {
    // The caller already owns the physical input and its measured holding.
    // Core admits the reservation; this method creates no Root or allowance.
    pub(crate) fn reserve_input_buffer(&mut self, nonce: i64, ticket: i32,
        bytes: usize, physical_copy_bytes: i64) -> wasmtime::Result<InputBuffer> {
        let length = i32::try_from(bytes)?;
        let handle = self.functions.buffer_reserve.call(&mut self.store,
            (nonce, ticket, length, physical_copy_bytes))?;
        if handle <= 0 { return Err(CoreFailure { operation: "buffer_reserve", code: handle }.into()); }
        Ok(InputBuffer { identity: self.identity.clone(), nonce, handle, bytes, closed: false })
    }

    fn original_buffer(&self, buffer: &InputBuffer) -> wasmtime::Result<()> {
        anyhow::ensure!(Arc::ptr_eq(&self.identity, &buffer.identity) && !buffer.closed,
                        "Foreign or closed original input buffer");
        Ok(())
    }

    pub(crate) fn fill_input_buffer(&mut self, buffer: &InputBuffer) -> wasmtime::Result<()> {
        self.original_buffer(buffer)?;
        for start in (0..buffer.bytes).step_by(BLOCK_BYTES) {
            let count = (buffer.bytes - start).min(BLOCK_BYTES);
            let code = self.functions.buffer_fill_block.call(&mut self.store,
                (buffer.nonce, buffer.handle, i32::try_from(start)?, i32::try_from(count)?))?;
            success("buffer_fill_block", code)?;
        }
        Ok(())
    }

    pub(crate) fn seal_input_buffer(&mut self, buffer: &InputBuffer) -> wasmtime::Result<()> {
        self.original_buffer(buffer)?;
        let code = self.functions.buffer_seal.call(&mut self.store, (buffer.nonce, buffer.handle))?;
        success("buffer_seal", code)
    }

    // No guest offset or memory slice escapes this operation. The mutable
    // Store borrow spans read_block and the immediate copy, with no callback,
    // guest reentry, memory growth or asynchronous suspension between them.
    pub(crate) fn read_input_block(&mut self, buffer: &InputBuffer, start: usize,
        destination: &mut [u8]) -> wasmtime::Result<()> {
        self.original_buffer(buffer)?;
        anyhow::ensure!(!destination.is_empty() && destination.len() <= BLOCK_BYTES &&
            start <= buffer.bytes && destination.len() <= buffer.bytes - start,
            "Invalid bounded original buffer read");
        let offset = self.functions.buffer_read_block.call(&mut self.store,
            (buffer.nonce, buffer.handle, i32::try_from(start)?, i32::try_from(destination.len())?))?;
        if offset < 0 { return Err(CoreFailure { operation: "buffer_read_block", code: offset }.into()); }
        self.memory.read(&self.store, usize::try_from(offset)?, destination)?;
        Ok(())
    }

    // Pending/failed cleanup leaves this same buffer usable only under Core's
    // retained state. There is no automatic close on error and no Drop ACK.
    pub(crate) fn close_input_buffer(&mut self, buffer: &mut InputBuffer) -> wasmtime::Result<i32> {
        self.original_buffer(buffer)?;
        let code = self.functions.buffer_close.call(&mut self.store, (buffer.nonce, buffer.handle))?;
        if code == 0 { buffer.closed = true; }
        Ok(code)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use wasmtime::Caller;
    use crate::abi::{StoreState, test_support};

    #[derive(Default)]
    struct PhysicalInputs {
        inputs: BTreeMap<i32, Arc<[u8]>>,
        copies: Vec<(i32, i32)>,
        scalar_reads: usize,
        cleanup_ready: bool,
        stop_ready: bool,
        short_copy: bool,
    }

    impl Imports for PhysicalInputs {
        fn input_copy(mut caller: Caller<'_, StoreState<Self>>, ticket: i32, start: i32,
            offset: i32, length: i32) -> wasmtime::Result<i32> {
            anyhow::ensure!(start >= 0 && offset >= 0 && (1..=16_384).contains(&length),
                            "Invalid physical copy bounds");
            let host = &mut caller.data_mut().host;
            let original = host.inputs.get(&ticket).ok_or_else(|| anyhow::anyhow!("Unknown original input"))?.clone();
            let start = usize::try_from(start)?;
            let count = usize::try_from(length)?;
            anyhow::ensure!(start <= original.len() && count <= original.len() - start,
                            "Physical copy exceeds original input");
            host.copies.push((i32::try_from(start)?, length));
            let copied = if host.short_copy { count - 1 } else { count };
            let memory = caller.get_export("memory").and_then(|value| value.into_memory())
                .ok_or_else(|| anyhow::anyhow!("Missing same-instance memory"))?;
            memory.write(&mut caller, usize::try_from(offset)?, &original[start..start + copied])?;
            Ok(i32::try_from(copied)?)
        }

        fn input_byte(mut caller: Caller<'_, StoreState<Self>>, _: i32, _: i32) -> wasmtime::Result<i32> {
            caller.data_mut().host.scalar_reads += 1;
            anyhow::bail!("No implicit scalar-transfer fallback")
        }

        fn input_cleanup(mut caller: Caller<'_, StoreState<Self>>, ticket: i32) -> wasmtime::Result<i32> {
            let host = &mut caller.data_mut().host;
            if !host.cleanup_ready { return Ok(1); }
            anyhow::ensure!(host.inputs.remove(&ticket).is_some(), "Unknown original cleanup input");
            Ok(0)
        }

        fn reader_stop(caller: Caller<'_, StoreState<Self>>, ticket: i32, reader: i32) -> wasmtime::Result<i32> {
            let host = &caller.data().host;
            anyhow::ensure!(host.inputs.contains_key(&ticket) && reader > 0, "Foreign original reader");
            Ok(if host.stop_ready { 0 } else { 1 })
        }
    }

    fn pool(nonce: i64) -> CoreInstance<PhysicalInputs> {
        let mut core = test_support::actual_module().instantiate(PhysicalInputs::default()).unwrap();
        // Explicit scalar diagnostic pool. This is not a normal Host/Run or
        // an imported execution child, and no unavailable grant is stubbed.
        assert_eq!(core.functions.buffer_open.call(&mut core.store,
            (nonce, 262_144, 16, 1_048_576, 100_000, 18, 16,
             32_000_000, 200_000_000, 16_777_216 + 262_144, 0)).unwrap(), 0);
        // A fresh diagnostic initialization uses the existing normal Host's
        // finite 1B bootstrap budget; this next scope selects its 32B operation
        // budget once. Neither is replenished inside a guest call or retry.
        core.store.set_fuel(32_000_000_000).unwrap();
        core
    }

    fn input(core: &mut CoreInstance<PhysicalInputs>, nonce: i64, ticket: i32, bytes: Arc<[u8]>) -> InputBuffer {
        let length = bytes.len();
        assert!(core.store.data_mut().host.inputs.insert(ticket, bytes).is_none());
        core.reserve_input_buffer(nonce, ticket, length,
            i64::try_from(length + std::mem::size_of::<InputBuffer>()).unwrap()).unwrap()
    }

    #[test]
    fn block_round_trip_feeds_the_original_core_preparation() {
        let nonce = 8201; let mut core = pool(nonce);
        let mut payload = vec![b'"']; payload.extend(vec![b'x'; 32_768]);
        payload.extend(b"\\u0000/\xf0\x9f\x98\x80/e\xcc\x81\"\r\n");
        let original: Arc<[u8]> = payload.into();
        let mut buffer = input(&mut core, nonce, 41, original.clone());
        assert!(core.read_input_block(&buffer, 0, &mut [0u8; 1]).is_err());
        core.fill_input_buffer(&buffer).unwrap(); core.seal_input_buffer(&buffer).unwrap();
        assert_eq!(core.store.data().host.copies, [(0, 16_384), (16_384, 16_384), (32_768, 19)]);
        assert_eq!(core.store.data().host.scalar_reads, 0);
        for start in (0..original.len()).step_by(BLOCK_BYTES) {
            let count = (original.len() - start).min(BLOCK_BYTES);
            let mut block = vec![0u8; count]; core.read_input_block(&buffer, start, &mut block).unwrap();
            assert_eq!(block, &original[start..start + count]);
        }
        assert!(Arc::ptr_eq(core.store.data().host.inputs.get(&41).unwrap(), &original));
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), -9);
        core.store.data_mut().host.cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), 0);
        core.store.data_mut().host.cleanup_ready = false;
        let environment: Arc<[u8]> = include_bytes!("../tests/fixtures/check-environment.json").as_slice().into();
        let mut environment_input = input(&mut core, nonce, 42, environment);
        core.fill_input_buffer(&environment_input).unwrap(); core.seal_input_buffer(&environment_input).unwrap();
        let environment = core.functions.program_install_environment.call(&mut core.store, (nonce, environment_input.handle)).unwrap();
        assert!(environment > 0, "Original Core environment refusal: {environment}");
        let mut query = input(&mut core, nonce, 43, br#""SELECT 41 AS n |> RESULT answer""#.as_slice().into());
        core.fill_input_buffer(&query).unwrap(); core.seal_input_buffer(&query).unwrap();
        let preparation = core.functions.program_reserve_preparation.call(&mut core.store, (nonce, environment, query.handle, 2)).unwrap();
        assert!(preparation > 0);
        assert_eq!(core.functions.program_prepare.call(&mut core.store, (nonce, preparation)).unwrap(), 0);
        assert_eq!(core.functions.program_prepared_results.call(&mut core.store, (nonce, preparation)).unwrap(), 1);
        assert_eq!(core.functions.program_close_preparation.call(&mut core.store, (nonce, preparation)).unwrap(), -9);
        core.store.data_mut().host.stop_ready = true;
        assert_eq!(core.functions.program_close_preparation.call(&mut core.store, (nonce, preparation)).unwrap(), 0);
        assert_eq!(core.functions.program_close_environment.call(&mut core.store, (nonce, environment)).unwrap(), 0);
        core.store.data_mut().host.cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut query).unwrap(), 0);
        assert_eq!(core.close_input_buffer(&mut environment_input).unwrap(), 0);
        assert_eq!(core.functions.buffer_close_pool.call(&mut core.store, (nonce,)).unwrap(), 0);
        assert_eq!(core.functions.buffer_reserved.call(&mut core.store, (nonce,)).unwrap(), 0);
        assert_eq!(core.store.data().host.scalar_reads, 0);
    }

    #[test]
    fn equal_numeric_handles_from_another_instance_do_not_copy_or_read() {
        let nonce = 8202; let mut left = pool(nonce); let mut right = pool(nonce);
        let mut left_buffer = input(&mut left, nonce, 1, b"\"left\"".as_slice().into());
        let mut right_buffer = input(&mut right, nonce, 1, b"\"right\"".as_slice().into());
        assert_eq!(left_buffer.handle, right_buffer.handle);
        assert!(right.fill_input_buffer(&left_buffer).is_err());
        assert!(right.read_input_block(&left_buffer, 0, &mut [0u8; 1]).is_err());
        assert!(right.store.data().host.copies.is_empty());
        right.fill_input_buffer(&right_buffer).unwrap(); right.seal_input_buffer(&right_buffer).unwrap();
        let mut output = [0u8; 7]; right.read_input_block(&right_buffer, 0, &mut output).unwrap();
        assert_eq!(&output, b"\"right\"");
        for (core, buffer) in [(&mut left, &mut left_buffer), (&mut right, &mut right_buffer)] {
            core.store.data_mut().host.cleanup_ready = true;
            assert_eq!(core.close_input_buffer(buffer).unwrap(), 0);
            assert!(core.fill_input_buffer(buffer).is_err());
            assert_eq!(core.functions.buffer_close_pool.call(&mut core.store, (nonce,)).unwrap(), 0);
        }
    }

    #[test]
    fn short_copy_failure_retains_the_original_cleanup_owner() {
        let nonce = 8203; let mut core = pool(nonce);
        let original: Arc<[u8]> = b"original".as_slice().into();
        let mut buffer = input(&mut core, nonce, 9, original.clone());
        core.store.data_mut().host.short_copy = true;
        let failure = core.fill_input_buffer(&buffer).unwrap_err();
        assert!(failure.downcast_ref::<CoreFailure>().unwrap().code < 0);
        assert_eq!(core.store.data().host.copies, [(0, 8)]);
        assert_eq!(core.store.data().host.scalar_reads, 0);
        assert!(Arc::ptr_eq(core.store.data().host.inputs.get(&9).unwrap(), &original));
        assert!(core.functions.buffer_allocated.call(&mut core.store, (nonce,)).unwrap() > 0);
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), -9);
        assert!(core.store.data().host.inputs.contains_key(&9));
        core.store.data_mut().host.cleanup_ready = true;
        assert_eq!(core.close_input_buffer(&mut buffer).unwrap(), 0);
        assert!(!core.store.data().host.inputs.contains_key(&9));
        assert_eq!(core.functions.buffer_close_pool.call(&mut core.store, (nonce,)).unwrap(), 0);
        assert_eq!(core.functions.buffer_reserved.call(&mut core.store, (nonce,)).unwrap(), 0);
    }
}
