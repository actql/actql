"""Opaque port caller identities/order; no physical Core/product acceptance."""
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_storage import LocalStorageError


class LocalStartDriverTests(unittest.TestCase):
    def fixture(self):
        host = object.__new__(InstalledLocalHost)
        run, compute, preflight, publisher, publication, projection = [object() for _ in range(6)]
        host._active = Mock()
        host._runs = SimpleNamespace(_run=Mock())
        host._source_free_computes = []
        records = [object(), object()]
        held = [SimpleNamespace(record=record, row=object(), capacity=object()) for record in records]
        host._payloads = held
        ports = Mock()
        def port(name, **kwargs):
            selected = Mock(**kwargs)
            ports.attach_mock(selected, name)
            setattr(host, '_' + name, selected)
        port('configure_original_compute', return_value=compute)
        port('prepare_original_publication', return_value=(preflight, publisher))
        port('execute_original_tasks', return_value=(object(), object()))
        port('capture_original_results', return_value=publication)
        port('prepare_original_payload', side_effect=held)
        for name in ('save_original_payload_intent', 'reserve_original_payload_capacity',
                     'save_original_payload_reserved', 'prepare_original_payload_writing',
                     'acquire_original_payload_file', 'stage_original_payload_file',
                     'open_original_payload_reader', 'prepare_original_commit_candidate',
                     'store_original_commit', 'prepare_original_store_observation'):
            port(name)
        for name in ('advance_original_payload_copy', 'advance_original_payload_sealing',
                     'advance_original_payload_reader'):
            port(name, side_effect=[False, True, False, True])
        port('advance_original_commit_candidate', side_effect=[None, projection])
        facts = tuple(SimpleNamespace(_record=record) for record in records)
        port('original_commit_reader_facts', return_value=facts)
        port('advance_original_store_observation', side_effect=[None, 'adopt_committed_index'])
        return host, ports, (run, compute, preflight, publisher, publication, projection, held, facts)

    def test_complete_original_inventory_is_written_once_then_observed_without_ack_or_state(self):
        host, ports, values = self.fixture()
        run, compute, preflight, publisher, publication, projection, held, facts = values
        self.assertIsNone(host._execute_original_admitted_run(run))
        host._runs._run.assert_called_once_with(run)
        host._configure_original_compute.assert_called_once_with(run)
        host._prepare_original_publication.assert_called_once_with(compute)
        host._execute_original_tasks.assert_called_once_with(compute, preflight, publisher)
        host._prepare_original_payload.assert_any_call(publication, 0)
        host._prepare_original_payload.assert_any_call(publication, 1)
        host._store_original_commit.assert_called_once_with(projection, facts,
            tuple((value.row, value.capacity) for value in held), publisher)
        host._prepare_original_store_observation.assert_called_once_with(projection, publisher)
        host._advance_original_store_observation.assert_called_with(projection)
        names = [call[0] for call in ports.mock_calls]
        self.assertLess(names.index('advance_original_payload_reader'), names.index('prepare_original_commit_candidate'))
        self.assertLess(names.index('store_original_commit'), names.index('prepare_original_store_observation'))
        self.assertFalse(any('ack' in name or 'run_state' in name or 'cancel' in name for name in names))

    def test_store_unknown_is_preserved_without_retry_new_observation_or_cleanup(self):
        host, ports, values = self.fixture()
        error = LocalStorageError('Original COMMIT observation is unknown')
        host._store_original_commit.side_effect = error
        with self.assertRaises(LocalStorageError) as failed:
            host._execute_original_admitted_run(values[0])
        self.assertIs(failed.exception, error)
        self.assertEqual(host._store_original_commit.call_count, 1)
        host._prepare_original_store_observation.assert_not_called()
        self.assertFalse(any('close' in call[0] or 'cancel' in call[0] for call in ports.mock_calls))
        self.assertEqual(len(host._payloads), 2)

    def test_retained_original_execution_refuses_replay_before_any_physical_port(self):
        host, ports, values = self.fixture()
        run = values[0]
        host._source_free_computes = [SimpleNamespace(start=SimpleNamespace(run=run))]
        with self.assertRaises(LocalStorageError):
            host._execute_original_admitted_run(run)
        self.assertEqual(ports.mock_calls, [])

    def test_task_failure_never_captures_result_or_starts_store_work(self):
        host, _, values = self.fixture()
        error = RuntimeError('Original task unknown')
        host._execute_original_tasks.side_effect = error
        with self.assertRaises(RuntimeError) as failed:
            host._execute_original_admitted_run(values[0])
        self.assertIs(failed.exception, error)
        host._capture_original_results.assert_not_called()
        host._store_original_commit.assert_not_called()


if __name__ == '__main__':
    unittest.main()
