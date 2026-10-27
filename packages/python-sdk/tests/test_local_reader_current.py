"""Public-base real File/SQLite fences; scalar Core, not SDK acceptance."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import _Output
from actql_sdk._local_storage import LocalStorageError
import test_local_host_binding as host_fixture
import test_local_saved_admission_caller as saved_fixture


def completed(counts, kind, original):
    def observe(*args):
        result = original(*args)
        counts[kind] += 1
        return result
    return observe


class SameReaderCurrentTests(unittest.TestCase):
    fixture = host_fixture.OriginalHostBindingTests.fixture

    def test_actual_host_reader_keeps_both_sql_fences_and_observes_each_file_once(self):
        observations = {}
        for mode in ('separate-reference', 'same-observer'):
            fixture = self.fixture()
            _, store, core, _, source, state, _, _, _, _, binding = fixture
            callbacks = core._journal_callbacks(binding._current.ticket)
            counts = {'file': 0, 'sqlRows': 0, 'completeFences': 0}

            def consume(_current):
                reader = callbacks.reader
                self.assertIs(callbacks.current, binding._current_observer)
                before = counts.copy()
                if mode == 'separate-reference':
                    # Independent test-only work reference, not a production
                    # dispatch option or a reader with a missing checker.
                    reader.check_fences(reader, ())
                    self.assertIsNone(callbacks.current())
                else:
                    self.assertEqual(callbacks.check_current(), 0)
                observations[mode] = {key: counts[key] - before[key] for key in before}

            with patch.object(source._root, 'observe_original',
                              side_effect=completed(counts, 'file', source._root.observe_original)), \
                    patch.object(state._root, 'observe_original',
                                 side_effect=completed(counts, 'file', state._root.observe_original)), \
                    patch.object(type(store._physical), 'read_row', autospec=True,
                                 side_effect=completed(counts, 'sqlRows', type(store._physical).read_row)), \
                    patch.object(store, '_fences_match_locked',
                                 side_effect=completed(counts, 'completeFences', store._fences_match_locked)):
                changes = store._connection.total_changes
                binding.inspect(consume)
                self.assertEqual(store._connection.total_changes, changes)
            self.assertIsNone(callbacks.reader)
            self.assertTrue(binding.close())
        self.assertEqual(observations, {
            'separate-reference': {'file': 12, 'sqlRows': 8, 'completeFences': 2},
            'same-observer': {'file': 6, 'sqlRows': 8, 'completeFences': 2},
        })
        print(json.dumps({'completed_public_host_checks': observations, 'writes': 0}))

    def test_public_saved_admission_caller_forwards_the_original_observer(self):
        helper = saved_fixture.SavedAdmissionCallerTests()
        self.addCleanup(helper.doCleanups)
        with TemporaryDirectory(prefix='actql-public-current-caller-') as directory:
            host, core, run, _, admission = helper.host(Path(directory))
            binding, store = host._installation.binding, host._installation._store
            source, state = binding._source, binding._state
            counts = {'file': 0, 'sqlRows': 0, 'completeFences': 0}
            checks = []
            actual_call = core._call

            def call(family, name, *args):
                if family == 'journal' and name in ('inspect', 'admission_length'):
                    journal = next(value for value in core._loans.values()
                                   if type(value) is _Output and value.family == 'journal' and value.handle == args[0])
                    callbacks = core._journal_callbacks(journal.ticket)
                    before = counts.copy()
                    self.assertEqual(callbacks.check_current(), 0)
                    checks.append({key: counts[key] - before[key] for key in before})
                return actual_call(family, name, *args)

            core._call = call
            with patch.object(source._root, 'observe_original',
                              side_effect=completed(counts, 'file', source._root.observe_original)), \
                    patch.object(state._root, 'observe_original',
                                 side_effect=completed(counts, 'file', state._root.observe_original)), \
                    patch.object(type(store._physical), 'read_row', autospec=True,
                                 side_effect=completed(counts, 'sqlRows', type(store._physical).read_row)), \
                    patch.object(store, '_fences_match_locked',
                                 side_effect=completed(counts, 'completeFences', store._fences_match_locked)):
                changes = store._connection.total_changes
                self.assertEqual(host._read_original_saved_admission(run), admission)
                self.assertEqual(store._connection.total_changes, changes)
            # Inspect plus first/copy/final lengths each enter the actual callback.
            self.assertEqual(checks, [{'file': 25, 'sqlRows': 18, 'completeFences': 2}] * 4)
            self.assertFalse(host._admission_observations)
            self.assertFalse(host._journal_outputs)
            self.assertIs(host._run_rows[0][0], run)
            self.assertFalse(store._connection.in_transaction)
            self.assertTrue(host.close())
            print(json.dumps({'completed_public_saved_caller_checks': checks, 'writes': 0,
                              'scalar_Core_not_actual_Run_or_admission': True}))

    def test_journal_refuses_a_missing_required_checker_without_legacy_dispatch(self):
        _, _, core, _, _, _, _, _, _, _, binding = self.fixture()
        callbacks = core._journal_callbacks(binding._current.ticket)

        def consume(_current):
            # Corrupt only the test reader after its actual factory supplied the
            # required checker. Missing code is not a legacy current route.
            object.__setattr__(callbacks.reader, 'check_fences_and_current', None)
            self.assertEqual(callbacks.check_current(), -41)
            self.assertIsInstance(callbacks.failure, TypeError)

        with self.assertRaises(TypeError) as caught:
            binding.inspect(consume)
        self.assertIs(caught.exception, callbacks.failure)
        self.assertIsNone(callbacks.reader)
        self.assertTrue(binding.close())

    def test_reader_construction_requires_the_combined_checker(self):
        _, _, core, _, _, _, _, _, _, _, binding = self.fixture()
        callbacks = core._journal_callbacks(binding._current.ticket)

        def consume(_current):
            reader = callbacks.reader
            with self.assertRaises(TypeError):
                type(reader)(reader.scan_after, reader.read, reader.owner,
                             reader.current, reader.check_fences)
            self.assertEqual(callbacks.check_current(), 0)

        binding.inspect(consume)
        self.assertTrue(binding.close())

    def test_distinct_failure_boolean_and_missing_callback_are_not_covered(self):
        for mode in ('failure', 'boolean', 'missing'):
            with self.subTest(mode=mode):
                _, _, core, _, _, _, _, _, _, _, binding = self.fixture()
                callbacks = core._journal_callbacks(binding._current.ticket)
                original, called = callbacks.current, []
                failure = OSError('Distinct current failed')

                def distinct():
                    called.append(1)
                    original()
                    if mode == 'boolean':
                        return True
                    raise failure

                def consume(_current):
                    callbacks.current = None if mode == 'missing' else distinct
                    self.assertEqual(callbacks.check_current(), -41)

                with self.assertRaises(Exception) as caught:
                    binding.inspect(consume)
                self.assertIs(caught.exception, callbacks.failure)
                self.assertEqual(called, [] if mode == 'missing' else [1])
                if mode == 'failure':
                    self.assertIs(caught.exception, failure)
                self.assertTrue(binding.close())

    def test_equal_but_distinct_callback_still_runs_without_equality_comparison(self):
        _, _, core, _, _, _, _, _, _, _, binding = self.fixture()
        callbacks = core._journal_callbacks(binding._current.ticket)
        original, called = callbacks.current, []

        class Distinct:
            def __eq__(self, other):
                raise AssertionError('Callback equality is not current identity')

            def __call__(self):
                called.append(1)
                return original()

        def consume(_current):
            callbacks.current = Distinct()
            self.assertEqual(callbacks.check_current(), 0)

        binding.inspect(consume)
        self.assertEqual(called, [1, 1])  # selected check and final Host validation
        self.assertTrue(binding.close())

    def test_changed_physical_row_is_refused_by_the_second_fence(self):
        _, store, _, _, _, _, _, _, _, _, binding = self.fixture()
        key = store.namespaced_key('client_local_settings', 'manifest')
        changing = [False]

        def current():
            binding._current_observer()
            if changing[0]:
                store._connection.execute('UPDATE core_bytes SET payload=? WHERE key=?',
                                          (b'changed-original', key))

        def inspect(reader):
            changing[0] = True
            # The exact observer is covered only after its second SQL fence.
            reader.check_fences_and_current(reader, (), current)

        with binding.fenced() as fences:
            with self.assertRaises(LocalStorageError):
                store.inspect_namespaces(fences, inspect=inspect, current=current)
        self.assertEqual(store.read(key).payload, b'original-selected-manifest')
        self.assertTrue(binding.close())

    def test_copied_and_expired_readers_retain_original_refusals(self):
        for mode in ('copy', 'expired'):
            with self.subTest(mode=mode):
                _, _, core, _, _, _, _, _, _, _, binding = self.fixture()
                callbacks = core._journal_callbacks(binding._current.ticket)
                held = []

                def consume(_current):
                    reader = callbacks.reader
                    if mode == 'copy':
                        with self.assertRaises(ValueError):
                            reader.check_fences_and_current(copy.copy(reader), (), callbacks.current)
                    else:
                        held.append(reader)

                if mode == 'copy':
                    with self.assertRaises(ValueError):
                        binding.inspect(consume)
                else:
                    binding.inspect(consume)
                    reader = held[0]
                    with self.assertRaises(ValueError):
                        reader.check_fences_and_current(reader, (), callbacks.current)
                self.assertTrue(binding.close())


if __name__ == '__main__':
    unittest.main()
