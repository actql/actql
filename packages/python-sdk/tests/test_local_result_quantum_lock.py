"""Actual result/publication caller boundaries over the existing scalar ports."""
from collections import Counter
from copy import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread, get_ident, local
import unittest
from unittest.mock import patch

import test_local_sdk_results as result_fixture


class _ObservedLock:
    """Observe actual outer releases; preserve the original RLock and thread."""
    def __init__(self, original, observe):
        self.original, self.observe = original, observe
        self.owner, self.depth = get_ident(), local()

    def acquire(self, *args, **kwargs):
        acquired = self.original.acquire(*args, **kwargs)
        if acquired:
            self.depth.value = getattr(self.depth, 'value', 0) + 1
        return acquired

    def release(self):
        self.depth.value -= 1
        self.original.release()
        if self.depth.value == 0 and get_ident() == self.owner:
            self.observe()

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, *_):
        self.release()


class ResultQuantumLockTests(unittest.TestCase):
    def fixture(self, directory):
        selected = result_fixture.SDKResultAssemblyTests()
        self.addCleanup(selected.doCleanups)
        return selected.host(Path(directory))

    def test_each_export_and_publication_quantum_gets_a_distinct_original_reader(self):
        with TemporaryDirectory(prefix='actql-result-reader-units-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.fixture(directory)
            results = host._execute_original_tasks(compute, preflight, publisher)
            binding = host._installation.binding
            inspect, groups = binding.inspect, []

            def read(consume):
                before = len(calls)
                inspect(consume)
                group = Counter((family, name) for family, name, _ in calls[before:])
                groups.append(group)
                for operation in [('result', 'feed'), ('result', 'advance'), ('publication', 'advance')]:
                    self.assertLessEqual(group[operation], 1,
                        'A current reader must not enclose a later continuation quantum')

            with patch.object(binding, 'inspect', side_effect=read):
                publication = host._capture_original_results(compute, preflight, results)
            for operation in [('result', 'feed'), ('result', 'advance'), ('publication', 'advance')]:
                self.assertGreaterEqual(sum(group[operation] for group in groups), 2)
            self.assertIs(host._publications[0], publication)
            self.assertIs(core._result_loans[results[0].handle], results[0])
            self.assertFalse(host._result_chunks)
            self.assertTrue(host.close())

    def test_same_owner_is_observable_between_result_and_publication_quanta_without_a_reader(self):
        with TemporaryDirectory(prefix='actql-result-unlock-units-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.fixture(directory)
            results = host._execute_original_tasks(compute, preflight, publisher)
            original = core._lock
            observed, failures = [], []

            def probe():
                try:
                    self.assertTrue(original.acquire(blocking=False))
                    try:
                        host._runs._compute(compute)
                        core._owned_result(results[0])
                        self.assertIsNone(host._installation.binding._observed_reader)
                        counts = Counter((family, name) for family, name, _ in calls)
                        observed.append((counts['result', 'feed'], counts['publication', 'advance']))
                    finally:
                        original.release()
                except BaseException as error:
                    failures.append(error)

            def released():
                thread = Thread(target=probe)
                thread.start()
                thread.join(1)
                self.assertFalse(thread.is_alive(), 'Observation cannot wait on an outer export lock')

            with patch.object(core, '_lock', _ObservedLock(original, released)):
                host._capture_original_results(compute, preflight, results)
            self.assertEqual(failures, [])
            self.assertIn(1, [feed for feed, _ in observed], 'The first feed must release before the second')
            self.assertIn(1, [advance for _, advance in observed], 'Publication continuation must release too')
            self.assertTrue(host.close())

    def test_foreign_compute_and_export_refuse_before_any_continuation(self):
        with TemporaryDirectory(prefix='actql-result-foreign-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.fixture(directory)
            results = host._execute_original_tasks(compute, preflight, publisher)
            before = len(calls)
            for selected, exports in [(copy(compute), results), (compute, (copy(results[0]),))]:
                with self.assertRaisesRegex(ValueError, 'Foreign'):
                    host._capture_original_results(selected, preflight, exports)
            self.assertEqual(len(calls), before)
            self.assertIs(core._result_loans[results[0].handle], results[0])
            self.assertFalse(host._result_chunks)
            self.assertFalse(host._publications)
            self.assertTrue(host.close())

    def test_current_file_change_between_quanta_retains_original_result_and_refuses_next_feed(self):
        with TemporaryDirectory(prefix='actql-result-current-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.fixture(directory)
            results = host._execute_original_tasks(compute, preflight, publisher)
            changed = False

            def released():
                nonlocal changed
                if not changed and any((family, name) == ('result', 'feed') for family, name, _ in calls):
                    changed = True
                    binding = host._installation.binding
                    os.chmod(binding._account.name, 0o644, dir_fd=binding._source._root._open())

            with patch.object(core, '_lock', _ObservedLock(core._lock, released)):
                with self.assertRaisesRegex(Exception, 'original generation'):
                    host._capture_original_results(compute, preflight, results)
            self.assertTrue(changed)
            self.assertEqual(sum((family, name) == ('result', 'feed') for family, name, _ in calls), 1)
            self.assertFalse(any(family == 'publication' for family, _, _ in calls))
            self.assertIs(core._result_loans[results[0].handle], results[0])
            self.assertFalse(host._result_chunks)
            self.assertTrue(host.close())

    def test_actual_close_between_quanta_fences_the_same_cursor_before_next_feed(self):
        with TemporaryDirectory(prefix='actql-result-close-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.fixture(directory)
            results = host._execute_original_tasks(compute, preflight, publisher)
            closing = False

            def released():
                nonlocal closing
                if not closing and any((family, name) == ('result', 'feed') for family, name, _ in calls):
                    closing = True
                    host.close()  # Actual existing cleanup, not a synthetic stop/ACK.

            with patch.object(core, '_lock', _ObservedLock(core._lock, released)):
                with self.assertRaisesRegex(ValueError, 'Host is unavailable'):
                    host._capture_original_results(compute, preflight, results)
            self.assertTrue(closing)
            self.assertEqual(sum((family, name) == ('result', 'feed') for family, name, _ in calls), 1)
            self.assertFalse(any(family == 'publication' for family, _, _ in calls))
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
