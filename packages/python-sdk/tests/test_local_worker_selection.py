"""Closed startup selections with controlled funding; no physical worker issued."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
from actql_sdk._local_worker_process import OriginalWorkerProcess
from actql_sdk._local_worker_slot import OriginalWorkerSlot
import test_local_worker_slot as slot_fixture


class WorkerSelectionTests(unittest.TestCase):
    def setUp(self):
        self.case = slot_fixture.WorkerSlotTests()
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.funding, self.slot = self.case.funding, self.case.slot
        self.options = dict(executable='/installed/python', executable_bytes=8192,
            executable_sha256='a' * 64, executable_image='/installed/python',
            executable_link=None, environment=(('LANG', 'C'),))

    def prepare(self, **changes):
        return OriginalWorkerProcess(self.funding, self.slot, **(self.options | changes))

    def test_path_objects_cannot_run_callbacks_during_selection(self):
        class CallbackPath(type(Path())):
            def __str__(self):
                raise AssertionError('Path callback ran')
            def is_absolute(self):
                raise AssertionError('Path callback ran')
        path = CallbackPath('/installed/python')
        with self.assertRaises(ValueError):
            OriginalWorkerSlot(self.funding, path)
        for key in ('executable', 'executable_image', 'executable_link'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.prepare(**{key: path})
        self.case.os_open.assert_not_called()

    def test_raw_path_bound_precedes_filesystem_encoding(self):
        with patch('actql_sdk._local_worker_slot.os.fsencode') as encode:
            with self.assertRaises(ValueError):
                OriginalWorkerSlot(self.funding, '/' + 'x' * 4096)
            with self.assertRaises(ValueError):
                self.prepare(executable='/' + 'x' * 4096)
            encode.assert_not_called()

    def test_encoded_path_boundary_preserves_exact_selected_bytes(self):
        path = '/' + '\U0001f642' * 1023 + 'abc'
        self.assertEqual(len(os.fsencode(path)), 4096)
        process = self.prepare(executable=path, executable_image=path)
        self.assertEqual(os.fsencode(process._executable), os.fsencode(path))
        self.assertEqual(process._environment, {'LANG': 'C'})
        self.case.os_open.assert_not_called()

    def test_multibyte_path_overflow_refuses_without_binding_slot(self):
        path = '/' + '\U0001f642' * 1024
        with self.assertRaises(ValueError):
            self.prepare(executable=path, executable_image=path)
        self.assertIsNone(self.slot._process_consumer)

    def test_environment_cardinality_refuses_before_path_copy_or_item_access(self):
        with patch('actql_sdk._local_worker_slot.os.fsencode') as encode:
            with self.assertRaises(ValueError):
                self.prepare(environment=(object(),) * 5)
            encode.assert_not_called()
        self.assertIsNone(self.slot._process_consumer)

    def test_environment_raw_bound_precedes_utf8_encoding(self):
        with self.assertRaisesRegex(ValueError, '^Invalid original selected worker environment$'):
            self.prepare(environment=(('LANG', '\ud800' * 4097),))
        self.assertIsNone(self.slot._process_consumer)

    def test_environment_encoded_boundary_and_closed_names(self):
        for environment in ((('PATH', '/bin'),), (('LANG', 'C'), ('LANG', 'C')),
                (('LANG', '\U0001f642' * 1025),)):
            with self.subTest(environment=environment), self.assertRaises(ValueError):
                self.prepare(environment=environment)
        process = self.prepare(environment=(('LANG', '\U0001f642' * 1024),))
        self.assertEqual(len(process._environment['LANG'].encode('utf-8')), 4096)
        self.case.os_open.assert_not_called()

    def test_missing_funding_precedes_any_selection_or_kernel_call(self):
        with patch('actql_sdk._local_worker_slot.os.fsencode') as encode:
            with self.assertRaises(LocalWorkerFundingUnavailable):
                OriginalWorkerSlot(None, object())
            with self.assertRaises(LocalWorkerFundingUnavailable):
                OriginalWorkerProcess(None, self.slot, **(self.options | {'executable': object()}))
            encode.assert_not_called()
        self.case.os_open.assert_not_called()
