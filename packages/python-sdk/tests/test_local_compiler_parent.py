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

    def acquire(self, fixture):
        control = fixture.backing.control
        def prepare(*args):
            control.events.append(('prepare', args[4], args[5]))
            args[-1]._obj.value = 11
            return 0
        control.library.actql_control_prepare_utf16_into = Function(prepare)
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


if __name__ == '__main__':
    unittest.main()
