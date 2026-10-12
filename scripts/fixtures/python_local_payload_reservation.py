"""Unexecuted private ABI29 cases for original capacity-bound Reserved CAS."""
import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from unittest.mock import patch

from actql_sdk._local_storage import ByteWrite, LocalByteStore, StoredBytes


def check_payload_reservation(fixture, payload_loan, facts, configuration, denied,
                              copy, call, assert_status, new_output_ticket):
    expected = json.loads((Path(__file__).parent / 'python-local-payload-reservation.json').read_text())
    cases = []
    parent, original_input = payload_loan(facts)
    assert_status('payload_request', 'produce', 0, parent, configuration)
    record = call('payload_record', 'reserve', parent, new_output_ticket(), expected['physical_copy_bytes'])
    assert record > 0, ('Original capacity record', record)
    assert_status('payload_record', 'produce', 0, record, configuration)
    assert_status('payload_reservation', 'reserve', -2, record, 65300, expected['physical_copy_bytes'])
    cases.append('unconfirmed_original_intent_cannot_prepare_reserved_transition')
    size = call('payload_record', 'length', record)
    assert 0 < size <= expected['max_record_bytes']
    initial = bytes(fixture.call('byte', record, index) for index in range(size))
    original = {'store_authority_cid': facts['store_authority_cid'],
                'material_generation_cid': facts['material_generation_cid']}
    capacity = {**original, 'capacity_namespace': expected['capacity_namespace'],
                'reserved_bytes': facts['max_payload_bytes'], 'reserved_objects': 1}

    class LostCapacityCAS(sqlite3.Connection):
        updates = 0
        lose = False

        def execute(self, sql, *args, **kwargs):
            if sql.startswith('UPDATE core_bytes'):
                self.updates += 1
            result = super().execute(sql, *args, **kwargs)
            if sql == 'COMMIT' and self.lose:
                self.lose = False
                raise OSError('Independent original Reserved CAS acknowledgement loss')
            return result

    connect = sqlite3.connect
    with TemporaryDirectory(prefix='actql-abi29-original-reservation-') as directory:
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **k, factory=LostCapacityCAS)):
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4,
                                max_record_bytes=65536, max_payload_bytes=262144) as store:
                key = facts['material_generation_cid']
                assert_status('payload_record', 'begin', 0, record, configuration)
                assert store.compare_exchange(key, None, initial) == 0
                initial_ack = copy({**original, 'physical_revision': 0, 'record_json': initial.decode()})
                assert_status('payload_record', 'confirm', 0, record, initial_ack, configuration)
                assert fixture.call('close', initial_ack) == 0
                assert store.reserve_capacity(expected['capacity_namespace'], key,
                                              facts['max_payload_bytes'], 1,
                                              facts['max_payload_bytes'], 1)
                observed = store.read_capacity(expected['capacity_namespace'], key)
                assert observed is not None
                child = call('payload_reservation', 'reserve', record, new_output_ticket(),
                             expected['physical_copy_bytes'])
                assert child > 0, ('Original Reserved child', child)
                for bad in (
                        {k: v for k, v in capacity.items() if k != 'reserved_objects'},
                        {**capacity, 'reserved_objects': None},
                        {**capacity, 'reserved_bytes': True},
                        {**capacity, 'extra': True}):
                    loan = copy(bad)
                    assert_status('payload_reservation', 'produce', -31, child, loan, configuration)
                    assert fixture.call('close', loan) == 0
                for bad in (
                        {**capacity, 'store_authority_cid': 'sha256:' + 'a' * 64},
                        {**capacity, 'material_generation_cid': 'sha256:' + 'a' * 64},
                        {**capacity, 'capacity_namespace': 'foreign'},
                        {**capacity, 'reserved_bytes': facts['max_payload_bytes'] - 1},
                        {**capacity, 'reserved_objects': 0}):
                    loan = copy(bad)
                    assert_status('payload_reservation', 'produce', -32, child, loan, configuration)
                    assert fixture.call('close', loan) == 0
                assert_status('payload_reservation', 'length', -33, child)
                assert store.read(key) == StoredBytes(0, initial)
                cases.append('closed_capacity_shape_and_foreign_facts_never_advance_original_record')
                loan = copy(capacity)
                assert_status('payload_reservation', 'produce', -32, child, loan, denied)
                assert_status('payload_reservation', 'produce', 0, child, loan, configuration)
                assert fixture.call('close', loan) == 0
                size = call('payload_reservation', 'length', child)
                assert 0 < size <= expected['max_record_bytes']
                successor = bytes(fixture.call('byte', child, index) for index in range(size))
                body = json.loads(successor)
                for name, value in expected['reserved_fields'].items():
                    assert body[name] == value, (name, body[name])
                initial_body = json.loads(initial)
                assert body['request_cid'] == initial_body['request_cid']
                assert body['request_json'] == initial_body['request_json']
                assert store.read(key) == StoredBytes(0, initial)
                assert_status('payload_reservation', 'validate', -32, child, denied)
                assert_status('payload_reservation', 'validate', 0, child, configuration)
                cases.append('prepared_successor_is_original_reserved_bytes_without_commit')
                write = ByteWrite(key, 0, successor)
                assert_status('payload_reservation', 'begin', 0, child, configuration)
                assert_status('payload_reservation', 'begin', -33, child, configuration)
                store._connection.lose = True
                try:
                    store.compare_exchange_reserved(write, observed)
                except OSError as error:
                    assert str(error) == 'Independent original Reserved CAS acknowledgement loss'
                else:
                    raise AssertionError('Missing independent Reserved CAS lost-ack case')
                assert store._connection.updates == 1
                assert_status('payload_reservation', 'close', -9, child)
                assert_status('payload_record', 'close', -9, record)
                assert_status('payload_request', 'close', -9, parent)
                assert fixture.call('close', original_input) == -9
                actual = store.read_exchange(write)
                assert actual == StoredBytes(1, successor)
                assert store.read_capacity(expected['capacity_namespace'], key) == observed
                assert store._connection.updates == 1
                cases.append('unknown_original_cas_retains_child_parent_input_and_same_capacity')
                ack = {**original, 'physical_revision': 1, 'record_json': successor.decode()}
                for bad in (
                        {**ack, 'store_authority_cid': 'sha256:' + 'a' * 64},
                        {**ack, 'material_generation_cid': 'sha256:' + 'a' * 64},
                        {**ack, 'physical_revision': 0},
                        {**ack, 'physical_revision': 2},
                        {**ack, 'record_json': initial.decode()}):
                    loan = copy(bad)
                    assert_status('payload_reservation', 'confirm', -32, child, loan, configuration)
                    assert fixture.call('close', loan) == 0
                loan = copy(ack)
                assert_status('payload_reservation', 'confirm', -32, child, loan, denied)
                assert_status('payload_reservation', 'confirm', 0, child, loan, configuration)
                assert_status('payload_reservation', 'confirm', 0, child, loan, configuration)
                assert fixture.call('close', loan) == 0
                assert store._connection.updates == 1
                cases.append('exact_original_successor_confirms_once_with_current_authority')
                allocated = fixture.call('allocated')
                fixture.cleanup_ready = False
                assert_status('payload_reservation', 'close', -9, child)
                assert fixture.call('allocated') == allocated
                assert_status('payload_record', 'close', -9, record)
                fixture.cleanup_ready = True
                assert_status('payload_reservation', 'close', 0, child)
                assert fixture.call('allocated') == allocated - (2 * 65536 + expected['physical_copy_bytes'])
                assert_status('payload_reservation', 'close', -2, child)
                assert store.read_capacity(expected['capacity_namespace'], key) == observed
                assert store.read(key) == StoredBytes(1, successor)
                assert_status('payload_record', 'close', 0, record)
                assert_status('payload_request', 'close', 0, parent)
                assert fixture.call('close', original_input) == 0
                cases.append('same_cleanup_retry_returns_transport_without_releasing_durable_capacity')
    assert cases == expected['cases']
    return cases
