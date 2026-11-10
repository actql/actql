"""Original task/export/capture caller over SQLite and scalar Core, not Wasm."""
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._local_storage import LocalStorageError
import test_local_sdk_preflight as preflight_fixture
import test_local_sdk_start as start_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKResultAssemblyTests(unittest.TestCase):
    def host(self, path):
        host, core, compute, _, _ = preflight_fixture.SDKPreflightAssemblyTests().host(path)
        self.addCleanup(host.close)
        preflight, publisher = host._prepare_original_publication(compute)
        previous = core._call
        calls = []
        failures = {}
        selected = [5013, 5019]
        tasks, completed = {}, set()
        chunks = {}
        exports = {}
        publications = {}
        next_chunk = [0]

        def input_bytes(handle):
            for value in core._loans.values():
                if value.handle == handle and value.ticket in core._inputs:
                    return core._inputs[value.ticket].payload
            self.fail('Missing original Core input')

        def call(family, name, *args):
            if family in ('task', 'result', 'publication') or (family, name) == ('publication_preflight', 'result_count'):
                calls.append((family, name, args))
                if (family, name) in failures:
                    return failures[family, name]
                if family == 'task':
                    if name == 'reserve_next_sdk':
                        self.assertEqual(args, (compute.core.handle, host._configuration.handle))
                        if selected:
                            handle = selected.pop(0)
                            tasks[handle] = {'feed': 0, 'advance': 0, 'final': 0, 'finalizing': False}
                            return handle
                        return 0 if completed == {5013, 5019} else -33
                    state = tasks[args[0]]
                    if name == 'feed': state['feed'] += 1
                    elif name == 'inputs_ready': return 0 if state['feed'] >= 2 else -7
                    elif name == 'advance': state['advance'] += 1
                    elif name == 'prepare_finalization':
                        self.assertGreaterEqual(state['advance'], 2)
                        state['finalizing'] = True
                    elif name == 'advance_finalization': state['final'] += 1
                    elif name == 'progress':
                        count = state['final'] if state['finalizing'] else state['advance']
                        return (int(count >= 2), 0, 1, 64)[args[1]]
                    elif name == 'complete':
                        self.assertGreaterEqual(state['final'], 2)
                        completed.add(args[0])
                    elif name not in ('start', 'started', 'close'):
                        self.fail('Unexpected task operation ' + name)
                    return 0
                if family == 'publication_preflight':
                    self.assertEqual(completed, {5013, 5019})
                    return 1
                if family == 'result':
                    if name == 'reserve_from_compute':
                        self.assertEqual(args, (compute.core.handle, 0, host._configuration.handle))
                        self.assertEqual(completed, {5013, 5019})
                        exports[6001] = {'feed': 0, 'advance': 0}
                        return 6001
                    if name == 'reserve_chunk':
                        self.assertEqual(args[0], 6001)
                        handle = 100 + args[1]
                        chunks[handle] = args[1]
                        return handle
                    if name == 'produce_chunk': next_chunk[0] += 1
                    elif name == 'chunk_final': return int(next_chunk[0] == 2)
                    elif name == 'close_chunk': return core._cleanup(chunks[args[0]])
                    elif name == 'feed': exports[args[0]]['feed'] += 1
                    elif name == 'inputs_ready': return 0 if exports[args[0]]['feed'] >= 2 else -7
                    elif name == 'advance': exports[args[0]]['advance'] += 1
                    elif name == 'progress': return (int(exports[args[0]]['advance'] >= 2), 1)[args[1]]
                    elif name not in ('start', 'finish_preparation', 'close'):
                        self.fail('Unexpected Result operation ' + name)
                    return 0
                if family == 'publication':
                    if name == 'reserve':
                        request = json.loads(input_bytes(args[1]))
                        self.assertEqual(request, {'results': [6001], 'max_work': 1000000, 'max_workspace_slots': 100000})
                        self.assertEqual(next_chunk[0], 2)
                        handle = 100 + args[2]
                        publications[handle] = [args[2], 0]
                        return handle
                    if name == 'advance': publications[args[0]][1] += 1
                    elif name == 'progress': return (int(publications[args[0]][1] >= 2), 1)[args[1]]
                    elif name in ('retire_output', 'close'): return core._cleanup(publications[args[0]][0])
                    elif name not in ('prepare', 'finish'): self.fail('Unexpected publication operation ' + name)
                    return 0
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return host, core, compute, preflight, publisher, calls, failures

    def test_core_selected_tasks_and_original_result_reach_receipt_without_ack_or_row_copy(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.host(Path(directory))
            before = start_fixture.SDKStartAssemblyTests().row(host)
            results = host._execute_original_tasks(compute, preflight, publisher)
            publication = host._capture_original_results(compute, preflight, results)
            after = start_fixture.SDKStartAssemblyTests().row(host)
            self.assertEqual((after.payload, after.generation), (before.payload, before.generation))
            self.assertEqual([args[0] for family, name, args in calls if (family, name) == ('task', 'complete')], [5013, 5019])
            self.assertFalse(any(name in ('byte', 'finish_commit', 'adopt_committed_index') for _, name, _ in calls))
            self.assertIs(core._loans[publication.ticket], publication)
            self.assertNotIn(publication.ticket, core._inputs)
            self.assertEqual(len(host._tasks), 2)
            self.assertEqual(len(host._result_exports), 1)
            self.assertTrue(host.close())

    def test_missing_task_handle_is_refusal_not_explicit_end(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, _, compute, preflight, publisher, calls, failures = self.host(Path(directory))
            failures['task', 'reserve_next_sdk'] = -2
            with self.assertRaises(LocalCoreError) as failure:
                host._execute_original_tasks(compute, preflight, publisher)
            self.assertEqual(failure.exception.code, -2)
            self.assertFalse(any(family in ('result', 'publication') for family, _, _ in calls))
            self.assertFalse(host._tasks)

    def test_unknown_task_advance_retains_exact_task_and_never_selects_result(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, failures = self.host(Path(directory))
            failures['task', 'advance'] = -41
            with self.assertRaises(LocalCoreError) as failure:
                host._execute_original_tasks(compute, preflight, publisher)
            self.assertEqual(failure.exception.code, -41)
            task = host._tasks[0]
            self.assertIs(core._task_loans[task.handle], task)
            self.assertFalse(any(family in ('result', 'publication') for family, _, _ in calls))

    def test_capture_failure_keeps_original_completed_result_without_durable_success(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, failures = self.host(Path(directory))
            results = host._execute_original_tasks(compute, preflight, publisher)
            failures['publication', 'advance'] = -32
            with self.assertRaises(LocalCoreError): host._capture_original_results(compute, preflight, results)
            self.assertIs(core._result_loans[results[0].handle], results[0])
            self.assertEqual(len(host._publications), 1)
            self.assertIs(core._loans[host._publications[0].ticket], host._publications[0])
            self.assertFalse(any(name in ('finish', 'finish_commit') for family, name, _ in calls if family == 'publication'))

    def test_chunk_cleanup_failure_retains_same_chunk_and_result_until_retry(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, _, failures = self.host(Path(directory))
            results = host._execute_original_tasks(compute, preflight, publisher)
            failures['result', 'close_chunk'] = -9
            with self.assertRaises(LocalProductCleanupPending): host._capture_original_results(compute, preflight, results)
            chunk = host._result_chunks[0]
            self.assertIs(core._loans[chunk.ticket], chunk)
            self.assertIn(chunk.ticket, core._inputs)
            self.assertIs(core._result_loans[results[0].handle], results[0])
            self.assertFalse(host.close())
            failures.pop(('result', 'close_chunk'))
            self.assertTrue(host.close())

    def test_post_current_failure_retains_original_selected_task_for_cleanup(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.host(Path(directory))
            original_validate = core.validate_host_current
            revoked = [False]

            def validate(value):
                if core._task_loans and not revoked[0]:
                    revoked[0] = True
                    raise LocalStorageError('Current changed after original task selection')
                return original_validate(value)

            with patch.object(core, 'validate_host_current', side_effect=validate):
                with self.assertRaisesRegex(LocalStorageError, 'after original task selection'):
                    host._execute_original_tasks(compute, preflight, publisher)
            task = next(iter(core._task_loans.values()))
            self.assertEqual(host._tasks, [task])
            self.assertIs(host._tasks[0], task)
            self.assertFalse(any((family, name) == ('task', 'start') for family, name, _ in calls))
            self.assertTrue(host.close())
            self.assertFalse(core._task_loans)

    def test_post_current_failure_retains_original_selected_result_for_cleanup(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.host(Path(directory))
            original_validate = core.validate_host_current
            revoked = [False]

            def validate(value):
                if core._result_loans and not revoked[0]:
                    revoked[0] = True
                    raise LocalStorageError('Current changed after original Result selection')
                return original_validate(value)

            with patch.object(core, 'validate_host_current', side_effect=validate):
                with self.assertRaisesRegex(LocalStorageError, 'after original Result selection'):
                    host._execute_original_tasks(compute, preflight, publisher)
            result = next(iter(core._result_loans.values()))
            self.assertEqual(host._result_exports, [result])
            self.assertIs(host._result_exports[0], result)
            self.assertFalse(any(family == 'publication' for family, _, _ in calls))
            self.assertTrue(host.close())
            self.assertFalse(core._result_loans)

    def test_bounded_steps_share_reader_but_loan_and_cleanup_boundaries_do_not(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.host(Path(directory))
            binding = host._installation.binding
            original = binding.inspect
            readers = []
            def inspect(consume):
                def entered(current):
                    readers.append(core._journal_callbacks(current.ticket).reader)
                    consume(current)
                original(entered)
            with patch.object(binding, 'inspect', side_effect=inspect):
                results = host._execute_original_tasks(compute, preflight, publisher)
                self.assertEqual(len(readers), 7)
                host._capture_original_results(compute, preflight, results)
                self.assertEqual(len(readers), 11)
            self.assertEqual(len({id(reader) for reader in readers}), 11)
            quanta = [args[1] for family, name, args in calls
                      if family == 'task' and name in ('feed', 'advance', 'advance_finalization')]
            self.assertTrue(quanta)
            self.assertEqual(set(quanta), {256})
            self.assertTrue(host.close())

    def test_grouped_task_refuses_file_change_before_next_step(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.host(Path(directory))
            binding = host._installation.binding
            original = core.feed_task
            def mutate(task, quantum):
                result = original(task, quantum)
                os.chmod(binding._account.name, 0o644, dir_fd=binding._source._root._open())
                return result
            with patch.object(core, 'feed_task', side_effect=mutate):
                with self.assertRaisesRegex(Exception, 'original generation'):
                    host._execute_original_tasks(compute, preflight, publisher)
            self.assertFalse(any((family, name) == ('task', 'advance') for family, name, _ in calls))
            self.assertEqual(len(host._tasks), 1)
            self.assertIs(core._task_loans[host._tasks[0].handle], host._tasks[0])
            self.assertTrue(host.close())

    def test_grouped_task_refuses_same_transaction_write_before_next_step(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, _ = self.host(Path(directory))
            store = host._installation._store
            original = core.feed_task
            def mutate(task, quantum):
                result = original(task, quantum)
                store._connection.execute('INSERT INTO core_bytes(key,generation,payload) VALUES(?,0,?)',
                    (store.namespaced_key('client_local_settings', 'unexpected'), b'{}'))
                return result
            with patch.object(core, 'feed_task', side_effect=mutate):
                with self.assertRaises(LocalStorageError):
                    host._execute_original_tasks(compute, preflight, publisher)
            self.assertFalse(any((family, name) == ('task', 'advance') for family, name, _ in calls))
            self.assertEqual(len(host._tasks), 1)
            self.assertTrue(host.close())

    def test_grouped_chunk_failure_retains_chunk_without_marker_or_cleanup(self):
        with TemporaryDirectory(prefix='actql-sdk-results-') as directory:
            host, core, compute, preflight, publisher, calls, failures = self.host(Path(directory))
            results = host._execute_original_tasks(compute, preflight, publisher)
            failures['result', 'produce_chunk'] = -41
            with self.assertRaises(LocalCoreError):
                host._capture_original_results(compute, preflight, results)
            self.assertFalse(any(family == 'result' and name in ('chunk_final', 'close_chunk')
                                 for family, name, _ in calls))
            chunk = host._result_chunks[0]
            self.assertIs(core._loans[chunk.ticket], chunk)
            self.assertIs(core._result_loans[results[0].handle], results[0])
            failures.clear()
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
