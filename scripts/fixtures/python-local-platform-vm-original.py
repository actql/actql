"""Actual tiny Wasmtime instances with an explicit fixture ABI-validation port.

These cases exercise original VM/caller/retirement identity, not the installed
Core ABI, Request funding, a normal image or the public README workflow.
"""
import copy
import hashlib
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))

import wasmtime
from actql_sdk._local_core import LocalCore, LocalCoreResources, LOCAL_CORE_ABI, _BUFFER_SIGNATURES


class PlatformVMOriginalTests(unittest.TestCase):
    def core(self):
        # This independent tiny module is deliberately not an ActQL Core.
        # Only module ABI validation is an explicit port; Engine/Store/Memory,
        # instance calls, Caller, memory growth and Store retirement are real.
        params = _BUFFER_SIGNATURES['open'][0]
        module = bytes(wasmtime.wat2wasm(f'''(module
          (import "actql_host" "execution_child_current"
            (func $current (param i64) (result i32)))
          (memory (export "memory") 1 256)
          (func (export "actql_host_abi_version") (result i32) i32.const {LOCAL_CORE_ABI})
          (func (export "actql_buffer_open") (param {params}) (result i32) i32.const 0)
          (func (export "actql_buffer_close_pool") (param i64) (result i32) i32.const 0)
          (func (export "actql_buffer_probe") (param i64) (result i32)
            local.get 0 call $current)
          (func (export "actql_buffer_grow") (param i64) (result i32)
            i32.const 1 memory.grow drop i32.const 0))'''))
        with patch('actql_sdk._local_core._validate_core_module'):
            core = LocalCore(module, digest=hashlib.sha256(module).hexdigest(),
                transfer_capacity=1024, slots=4,
                resources=LocalCoreResources(1000, 4, 16, 4096, 4096, 16781312))
        self.addCleanup(core.close)
        # Raw-Wasm diagnostics have no selected ordinary initialization. Enter
        # the same private callee explicitly; the normal constructor's call is
        # checked as source correspondence, not claimed executed here.
        core._observe_platform_vm(wasmtime)
        return core

    def test_original_memory_growth_and_caller_do_not_issue_child_permission(self):
        core = self.core()
        original = core._platform_vm_original
        self.assertEqual(core._require_platform_vm_current(), 65536)
        self.assertEqual(core._call('buffer', 'probe'), -42)
        self.assertEqual(core._call('buffer', 'grow'), 0)
        self.assertEqual(core._require_platform_vm_current(), 131072)
        self.assertIs(core._platform_vm_original, original)
        self.assertIsNone(core._physical_holding)
        self.assertIsNone(core._physical_child_control)
        with self.assertRaises(ValueError):
            core._observe_platform_vm(wasmtime)

    def test_foreign_same_limits_store_instance_copy_and_nonce_are_refused(self):
        core = self.core()
        other = self.core()
        original_store = core._store
        core._store = other._store
        try:
            with self.assertRaises(ValueError): core._require_platform_vm_current()
        finally:
            core._store = original_store
        changed = copy.copy(core)
        with self.assertRaises(ValueError): changed._require_platform_vm_current()
        # This is a real foreign Caller with the original nonce, not a fake
        # Caller/context/address supplied directly to the checked function.
        callbacks = []
        # A separate real import is bound before instantiation; invoke through
        # the real constructor's fixed import's bound method via a fresh core.
        with patch.object(LocalCore, '_unavailable_execution_child', foreign_method(core, callbacks)):
            third = self.core()
        self.assertEqual(third._call('buffer', 'probe'), -42)
        self.assertEqual(callbacks, [third._nonce])
        with self.assertRaises(ValueError):
            core._require_platform_vm_current(nonce=True)

    def test_same_store_close_failure_retains_original_until_actual_retirement(self):
        core = self.core()
        original = core._platform_vm_original
        store, instance = core._store, core._instance
        with patch.object(store, 'close', side_effect=RuntimeError('independent close failure')):
            with self.assertRaisesRegex(RuntimeError, 'independent close failure'):
                core.close()
        self.assertIs(core._store, store)
        self.assertIs(core._instance, instance)
        self.assertIs(core._platform_vm_original, original)
        self.assertFalse(core._closed)
        # Closing permits identity observation, not a new operation/admission.
        core._require_platform_vm_current()
        self.assertTrue(core.close())
        self.assertIsNone(core._platform_vm_original)
        self.assertIsNone(core._instance)
        self.assertIsNone(core._store)
        with self.assertRaises(ValueError): core._require_platform_vm_current()

    def test_callback_cannot_drop_original_vm_metadata_before_outer_return(self):
        def lose(core, caller, nonce, *arguments):
            core._require_platform_vm_current(caller=caller, nonce=nonce)
            core._platform_vm_original = None
            return -42
        with patch.object(LocalCore, '_unavailable_execution_child', lose):
            core = self.core()
        original = core._platform_vm_original
        try:
            with self.assertRaises(ValueError):
                core._call('buffer', 'probe')
        finally:
            # Retain the SAME original for explicit cleanup, never recapture.
            core._platform_vm_original = original
        self.assertTrue(core._closing)


def foreign_method(original, calls):
    def invoke(core, caller, nonce, *arguments):
        calls.append(nonce)
        try:
            original._require_platform_vm_current(caller=caller, nonce=original._nonce)
        except ValueError:
            pass
        else:
            raise AssertionError('Foreign actual Caller was admitted')
        core._require_platform_vm_current(caller=caller, nonce=nonce)
        return -42
    return invoke


if __name__ == '__main__':
    unittest.main()
