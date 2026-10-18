"""Source-bound compiler assembly/partial custody; scalar Native ports only."""
from ctypes import c_void_p
import hashlib
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

import test_local_image_compiler_holding as holding
from test_local_native_domain_custody import DomainFixture
from test_local_native_control_custody import Function
from test_local_native_process_custody import ProcessFixture, Error as ProcessError
from actql_sdk._local_worker_slot import _OriginalDescriptor

compiler = holding.compiler


class CompilerParentTests(unittest.TestCase):
    def setUp(self):
        self.fixture = holding.CompilerHoldingTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.original = self.fixture.original()
        selected = compiler._compiler_holding_original(self.original)
        size = selected.capacity_bytes
        self.body = {'scope': 'image_compiler_parent_only', 'holding_sha256': selected.recipe.hex(),
            'parent': dict(bytes=size, work=20, attempts=8, holdings=4, transfer=30,
                           retained=0, execution=size, control_envelope=65536),
            'child': dict(bytes=size // 2, work=2, attempts=1, holdings=1,
                          transfer=3, retained=0, execution=size // 2)}
        self.path = self.fixture.case.source / 'packages/python-local-runtime/selected-compiler-parent.json'
        self.write_original()
        path = self.fixture.case.root / 'backing'
        self.descriptor = _OriginalDescriptor(os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600))
        self.addCleanup(self.descriptor.close)
        os.ftruncate(self.descriptor.value, size)

    def write_original(self):
        self.path.write_text(json.dumps(self.body))
        self.fixture.case.commit()
        self.fixture.case.core['source_sha'] = self.fixture.case.head
        self.fixture.case.write_receipts()
        self.original = compiler.verify(self.fixture.case.module_file, self.fixture.case.head)
        self.original = compiler._runtime_original(self.original, self.fixture.fixture.preparation(self.original))
        self.selected = compiler._compiler_holding_original(self.original)

    def acquire(self, fixture, *, initialize=None, current=None):
        control = fixture.backing.control
        def prepare(*args):
            control.events.append(('prepare', args[4], args[5]))
            args[-1]._obj.value = 11
            return 0
        control.library.actql_control_prepare_utf16_into = Function(prepare)
        def start(slot):
            control.events.append(('runtime_initialize',))
            slot._obj.value = 701
            return 0
        control.library.actql_control_runtime_initialize_into = Function(initialize or start)
        control.library.actql_control_runtime_current = Function(current or (lambda slot: 0 if slot.value == 701 else -1))
        with patch.object(compiler, 'CDLL', return_value=control.library):
            return compiler._acquire_compiler_parent(self.original, self.selected, self.descriptor)

    def test_original_key_order_is_not_an_execution_budget(self):
        expected = compiler._compiler_parent_original(self.original, self.selected)
        self.body['parent'] = dict(reversed(list(self.body['parent'].items())))
        self.body['child'] = dict(reversed(list(self.body['child'].items())))
        self.write_original()
        reordered = compiler._compiler_parent_original(self.original, self.selected)
        self.assertEqual((reordered.parent, reordered.child), (expected.parent, expected.child))
        self.assertNotEqual(reordered.recipe, expected.recipe)
        self.assertEqual(reordered.recipe, hashlib.sha256(self.path.read_bytes()).digest())

    def test_missing_foreign_or_dirty_original_refuses_before_library_load(self):
        self.path.write_text(self.path.read_text() + '\n')
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Native load')):
            with self.assertRaisesRegex(ValueError, 'committed original'):
                compiler._acquire_compiler_parent(self.original, self.selected, self.descriptor)
        self.path.unlink()
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Native load')):
            with self.assertRaisesRegex(ValueError, 'compiler parent is unavailable'):
                compiler._acquire_compiler_parent(self.original, self.selected, self.descriptor)
        self.body['holding_sha256'] = '0' * 64
        self.write_original()
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Native load')):
            with self.assertRaisesRegex(ValueError, 'source-original envelope'):
                compiler._acquire_compiler_parent(self.original, self.selected, self.descriptor)

    def test_changed_descriptor_size_refuses_before_native_load(self):
        os.ftruncate(self.descriptor.value, self.selected.capacity_bytes - 1)
        with patch.object(compiler, 'CDLL', side_effect=AssertionError('Native load')):
            with self.assertRaisesRegex(ValueError, 'selected backing'):
                compiler._acquire_compiler_parent(self.original, self.selected, self.descriptor)

    def test_native_owner_acquires_and_keeps_same_parent_domain_and_descriptor(self):
        f = DomainFixture()
        parent = self.acquire(f)
        self.assertIs(parent.domain._owner, parent.host)
        self.assertIs(parent.domain._scope, parent.backing)
        self.assertIs(parent.domain._descriptor, self.descriptor)
        self.assertIs(parent.domain._functions.library, parent.library)
        self.assertIs(parent.host._borrowed_fd, self.descriptor)
        self.assertEqual(sum(e[0:2] == ('call', 3) for e in f.events), 1)
        parent.close_unstarted(); parent.close_unstarted()
        self.assertTrue(parent._closed)
        self.assertTrue(parent.domain._closed and parent.backing._closed and parent.host._closed)
        self.assertFalse(self.descriptor.close_attempted)
        self.assertEqual(sum(e[0] == 'prepare' for e in f.backing.control.events), 1)
        self.assertEqual(sum(e[0] == 'runtime_initialize' for e in f.backing.control.events), 1)
        self.assertEqual(parent.runtime.slot.value, 701)
        self.assertIs(parent.runtime.library, parent.library)
        # Arena cleanup is not a process-global Runtime retirement ACK.
        self.assertTrue(parent.runtime._initialized)

    def test_initializer_reply_loss_keeps_slot_library_and_no_host_acquire(self):
        f = DomainFixture()
        calls = []
        def lost(slot):
            calls.append('initialize')
            slot._obj.value = 701
            raise OSError('lost original initializer reply')
        with self.assertRaises(compiler.CompilerControlInitializationError) as caught:
            self.acquire(f, initialize=lost)
        runtime = caught.exception.cleanup_runtime
        self.assertIs(runtime.library, f.backing.control.library)
        self.assertEqual(runtime.slot.value, 701)
        self.assertIs(runtime._unknown, caught.exception)
        self.assertFalse(runtime._initialized)
        self.assertFalse(any(e[0] == 'prepare' for e in f.backing.control.events))
        with self.assertRaises(compiler.CompilerControlInitializationError) as again:
            runtime.current()
        self.assertIs(again.exception, caught.exception)
        self.assertEqual(calls, ['initialize'])
        self.assertFalse(self.descriptor.close_attempted)

    def test_failed_initializer_retains_original_slot_without_another_init(self):
        f = DomainFixture(); calls = []
        def refused(slot):
            calls.append('initialize')
            slot._obj.value = 701
            return -3
        with self.assertRaises(compiler.CompilerControlInitializationError) as caught:
            self.acquire(f, initialize=refused)
        self.assertEqual(caught.exception.cleanup_runtime.slot.value, 701)
        with self.assertRaises(compiler.CompilerControlInitializationError):
            caught.exception.cleanup_runtime.current()
        self.assertEqual(calls, ['initialize'])
        self.assertFalse(any(e[0] == 'prepare' for e in f.backing.control.events))

    def test_empty_success_and_changed_runtime_current_refuse_before_host(self):
        for initialize, current in ((lambda slot: 0, None), (None, lambda slot: -1)):
            with self.subTest(initializer=initialize is not None):
                f = DomainFixture()
                with self.assertRaises(compiler.CompilerControlInitializationError):
                    self.acquire(f, initialize=initialize, current=current)
                self.assertFalse(any(e[0] == 'prepare' for e in f.backing.control.events))

    def test_missing_initialization_abi_never_assumes_an_initialized_library(self):
        f = DomainFixture()
        library = f.backing.control.library
        with patch.object(compiler, 'CDLL', return_value=library):
            with self.assertRaises(compiler.CompilerControlInitializationError) as caught:
                compiler._acquire_compiler_parent(self.original, self.selected, self.descriptor)
        self.assertIs(caught.exception.cleanup_runtime.library, library)
        self.assertIsNone(caught.exception.cleanup_runtime.slot.value)
        self.assertFalse(any(e[0] == 'prepare' for e in f.backing.control.events))
        self.assertFalse(self.descriptor.close_attempted)

    def test_runtime_foreign_process_or_thread_refuses_before_current_ffi(self):
        f = DomainFixture(); calls = []
        parent = self.acquire(f, current=lambda slot: calls.append('current') or 0)
        before = list(calls)
        with patch.object(compiler.os, 'getpid', return_value=parent.runtime._process + 1):
            with self.assertRaisesRegex(ValueError, 'process/thread'):
                parent.runtime.current()
        with patch.object(compiler, 'current_thread', return_value=object()):
            with self.assertRaisesRegex(ValueError, 'process/thread'):
                parent.runtime.current()
        self.assertEqual(calls, before)
        parent.close_unstarted()

    def test_domain_reply_loss_keeps_all_originals_and_no_parent_cleanup(self):
        f = DomainFixture(); f.prepare_fault = OSError('lost original domain reply')
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as observed:
            self.acquire(f)
        parent = observed.exception.cleanup_parent
        self.assertIsNotNone(parent.domain)
        self.assertIs(parent.domain._descriptor, self.descriptor)
        self.assertIsNotNone(parent.domain._reply.value)
        events = (list(f.events), list(f.backing.events), list(f.backing.control.events))
        with self.assertRaises(type(parent.domain._unknown)):
            parent.close_unstarted()
        self.assertEqual(events, (f.events, f.backing.events, f.backing.control.events))
        self.assertFalse(parent._closed or self.descriptor.close_attempted)

    def test_original_transfer_reply_loss_retains_same_domain_before_material(self):
        f = DomainFixture()
        transfer = f.functions.transfer.call
        def lose(*args):
            transfer(*args)
            raise OSError('lost same original transfer response')
        f.functions.transfer.call = lose
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as observed:
            self.acquire(f)
        parent = observed.exception.cleanup_parent
        self.assertIsNotNone(parent.domain._reply.value)
        self.assertEqual(sum(e[0:2] == ('call', 3) for e in f.events), 1)
        before = list(f.events)
        with self.assertRaises(type(parent.domain._unknown)):
            parent.close_unstarted()
        self.assertEqual(before, f.events)
        self.assertFalse(parent._closed or self.descriptor.close_attempted)

    def test_process_bound_domain_is_not_retired_as_unstarted(self):
        f = DomainFixture(); parent = self.acquire(f)
        parent.domain._worker_process_original = object()
        before = list(f.backing.events)
        with self.assertRaisesRegex(ValueError, 'process custody'):
            parent.close_unstarted()
        self.assertEqual(before, f.backing.events)
        self.assertFalse(parent._closed)

    def process_parent(self):
        native = DomainFixture()
        parent = self.acquire(native)
        process = ProcessFixture(original=native, domain=parent.domain)
        return parent, process

    def test_selected_child_process_blocks_parent_before_any_backing_return(self):
        parent, native = self.process_parent()
        process = parent.prepare_process(path='/private/compiler.slot', nonce=19)
        self.assertIs(parent.domain._installed_process_original, process)
        self.assertIs(process._domain, parent.domain)
        self.assertEqual(native.preparations, [(19, self.body['child']['retained'],
                                                self.body['child']['execution'])])
        before = (list(native.events), list(native.original.backing.events))
        with self.assertRaisesRegex(ValueError, 'process custody'):
            parent.close_unstarted()
        self.assertEqual(before, (native.events, native.original.backing.events))
        self.assertFalse(parent.backing._closed or parent._closed or self.descriptor.close_attempted)
        process.close_unstarted()
        parent.close_unstarted()
        self.assertTrue(parent._closed)

    def test_lost_process_preparation_keeps_same_parent_and_partial_slot(self):
        parent, native = self.process_parent()
        native.prepare_fault = OSError('lost original process preparation')
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as caught:
            parent.prepare_process(path='/private/compiler.slot', nonce=19)
        self.assertIs(caught.exception.cleanup_parent, parent)
        process = parent.domain._installed_process_original
        self.assertIsNotNone(process._reply.value)
        self.assertTrue(process._unknown.unknown)
        before = (list(native.events), list(native.original.backing.events))
        with self.assertRaisesRegex(ValueError, 'process custody'):
            parent.close_unstarted()
        with self.assertRaises(ValueError):
            parent.prepare_process(path='/private/new.slot', nonce=20)
        self.assertEqual(before, (native.events, native.original.backing.events))
        self.assertEqual(len(native.preparations), 1)

    def test_known_partial_process_refusal_retains_same_cleanup(self):
        parent, native = self.process_parent()
        native.issue = 6
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as caught:
            parent.prepare_process(path='/private/compiler.slot', nonce=19)
        self.assertIs(caught.exception.cleanup_parent, parent)
        self.assertIsInstance(caught.exception.__cause__, ProcessError)
        self.assertFalse(caught.exception.__cause__.unknown)
        process = parent.domain._installed_process_original
        with self.assertRaisesRegex(ValueError, 'process custody'):
            parent.close_unstarted()
        native.issue = 0
        process.close_unstarted(); parent.close_unstarted()
        self.assertTrue(parent._closed)

    def test_no_process_refusal_keeps_parent_cleanup_available(self):
        parent, native = self.process_parent()
        native.issue, native.present = 1, False
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as caught:
            parent.prepare_process(path='/private/compiler.slot', nonce=19)
        self.assertIs(caught.exception.cleanup_parent, parent)
        self.assertIsNone(parent.domain._installed_process_original)
        parent.close_unstarted()
        self.assertTrue(parent._closed)

    def test_busy_process_entry_does_not_change_parent_or_existing_busy(self):
        parent, native = self.process_parent()
        parent.host._busy = True
        with self.assertRaises(ValueError):
            parent.prepare_process(path='/private/compiler.slot', nonce=19)
        self.assertTrue(parent.host._busy)
        self.assertIsNone(parent.domain._installed_process_original)
        self.assertEqual(native.events, [])
        parent.host._busy = False
        process = parent.prepare_process(path='/private/compiler.slot', nonce=19)
        process.close_unstarted(); parent.close_unstarted()

    def test_changed_parent_descriptor_has_no_process_ffi(self):
        parent, native = self.process_parent()
        parent.descriptor = _OriginalDescriptor(-1)
        with self.assertRaisesRegex(ValueError, 'parent domain'):
            parent.prepare_process(path='/private/compiler.slot', nonce=19)
        self.assertEqual(native.events, [])
        self.assertIsNone(parent.domain._installed_process_original)
        parent.descriptor = self.descriptor
        parent.close_unstarted()


if __name__ == '__main__':
    unittest.main()
