"""Unexecuted private ABI30 Writing/Owned boundaries, with synthetic Host identity."""
import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from unittest.mock import patch

from actql_sdk._local_storage import ByteWrite, LocalByteStore, StoredBytes


def check_payload_writing(fixture, payload_loan, facts, configuration, denied,
                          copy, call, assert_status, new_output_ticket):
    expected = json.loads((Path(__file__).parent / 'python-local-payload-writing.json').read_text())
    cases = []
    parent, original_input = payload_loan(facts)
    assert_status('payload_request', 'produce', 0, parent, configuration)
    record = call('payload_record', 'reserve', parent, new_output_ticket(), expected['physical_copy_bytes'])
    assert record > 0, ('Original writing parent', record)
    assert_status('payload_record', 'produce', 0, record, configuration)
    size = call('payload_record', 'length', record)
    assert 0 < size <= expected['max_record_bytes']
    initial = bytes(fixture.call('byte', record, index) for index in range(size))
    original = {'store_authority_cid': facts['store_authority_cid'],
                'material_generation_cid': facts['material_generation_cid']}

    def output(child, family):
        size = call(family, 'length', child)
        assert 0 < size <= expected['max_record_bytes']
        return bytes(fixture.call('byte', child, index) for index in range(size))

    def confirm(family, child, revision, payload, authority=configuration):
        observation = copy({**original, 'physical_revision': revision, 'record_json': payload.decode()})
        assert_status(family, 'confirm', 0, child, observation, authority)
        assert fixture.call('close', observation) == 0

    class LostOwnedCAS(sqlite3.Connection):
        updates = 0
        lose = False

        def execute(self, sql, *args, **kwargs):
            if sql.startswith('UPDATE core_bytes'):
                self.updates += 1
            result = super().execute(sql, *args, **kwargs)
            if sql == 'COMMIT' and self.lose:
                self.lose = False
                raise OSError('Independent original Owned CAS acknowledgement loss')
            return result

    connect = sqlite3.connect
    with TemporaryDirectory(prefix='actql-abi30-original-writing-') as directory:
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **k, factory=LostOwnedCAS)):
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4,
                                max_record_bytes=65536, max_payload_bytes=262144) as store:
                key = facts['material_generation_cid']
                assert_status('payload_record', 'begin', 0, record, configuration)
                assert store.compare_exchange(key, None, initial) == 0
                confirm('payload_record', record, 0, initial)
                assert_status('payload_writing', 'reserve', -2, record, 1, 65400, expected['physical_copy_bytes'])
                assert store.reserve_capacity(expected['capacity_namespace'], key,
                                              facts['max_payload_bytes'], 1,
                                              facts['max_payload_bytes'], 1)
                reservation = store.read_capacity(expected['capacity_namespace'], key)
                assert reservation is not None
                reserved = call('payload_reservation', 'reserve', record, new_output_ticket(), expected['physical_copy_bytes'])
                assert reserved > 0
                capacity = copy({**original, 'capacity_namespace': expected['capacity_namespace'],
                                 'reserved_bytes': facts['max_payload_bytes'], 'reserved_objects': 1})
                assert_status('payload_reservation', 'produce', 0, reserved, capacity, configuration)
                assert fixture.call('close', capacity) == 0
                reserved_wire = output(reserved, 'payload_reservation')
                assert_status('payload_reservation', 'begin', 0, reserved, configuration)
                assert store.compare_exchange_reserved(ByteWrite(key, 0, reserved_wire), reservation) == 1
                confirm('payload_reservation', reserved, 1, reserved_wire)
                assert_status('payload_writing', 'reserve', -3, record, 1, 65400, expected['physical_copy_bytes'])
                assert_status('payload_reservation', 'close', 0, reserved)
                writing = call('payload_writing', 'reserve', record, 1, new_output_ticket(), expected['physical_copy_bytes'])
                assert writing > 0
                assert_status('payload_writing', 'reserve', -3, record, 1, 65400, expected['physical_copy_bytes'])
                assert_status('payload_writing', 'reserve', -2, record, 2, 65400, expected['physical_copy_bytes'])
                cases.append('original_reserved_record_and_single_child_are_required')
                assert_status('payload_writing', 'produce', -32, writing, 0, denied)
                assert_status('payload_writing', 'produce', 0, writing, 0, configuration)
                writing_wire = output(writing, 'payload_writing')
                body = json.loads(writing_wire)
                for name, value in expected['writing_fields'].items():
                    assert body[name] == value, (name, body[name])
                reserved_body = json.loads(reserved_wire)
                assert body['request_cid'] == reserved_body['request_cid']
                assert body['request_json'] == reserved_body['request_json']
                assert store.read(key) == StoredBytes(1, reserved_wire)
                assert store.read_capacity(expected['capacity_namespace'], key) == reservation
                cases.append('writing_preparation_keeps_original_reserved_record_and_capacity')
                assert_status('payload_writing', 'begin', 0, writing, configuration)
                assert_status('payload_writing', 'begin', -33, writing, configuration)
                assert store.compare_exchange_reserved(ByteWrite(key, 1, writing_wire), reservation) == 2
                confirm('payload_writing', writing, 2, writing_wire)
                confirm('payload_writing', writing, 2, writing_wire)
                assert store._connection.updates == 2
                assert_status('payload_writing', 'close', 0, writing)
                assert_status('payload_writing', 'reserve', -2, record, 1, 65400, expected['physical_copy_bytes'])
                cases.append('exact_writing_successor_advances_the_same_record_once')
                owned = call('payload_writing', 'reserve', record, 2, new_output_ticket(), expected['physical_copy_bytes'])
                assert owned > 0
                identity = {**original, 'device': expected['ownership_device'], 'inode': expected['ownership_inode']}
                assert_status('payload_writing', 'produce', -31, owned, 0, configuration)
                for bad in (
                        {**identity, 'device': 9007199254740993},
                        {**identity, 'device': None}, {**identity, 'device': True},
                        {**identity, 'device': ''}, {**identity, 'device': '+1'},
                        {**identity, 'device': '01'}, {**identity, 'device': '-1'},
                        {**identity, 'inode': '18446744073709551616'},
                        {**identity, 'extra': 'field'},
                        {k: v for k, v in identity.items() if k != 'inode'}):
                    loan = copy(bad)
                    assert_status('payload_writing', 'produce', -31, owned, loan, configuration)
                    assert fixture.call('close', loan) == 0
                for bad in ({**identity, 'store_authority_cid': 'sha256:' + 'a' * 64},
                            {**identity, 'material_generation_cid': 'sha256:' + 'a' * 64}):
                    loan = copy(bad)
                    assert_status('payload_writing', 'produce', -32, owned, loan, configuration)
                    assert fixture.call('close', loan) == 0
                assert store.read(key) == StoredBytes(2, writing_wire)
                cases.append('owned_observation_rejects_noncanonical_uint64_and_foreign_bindings')
                loan = copy(identity)
                assert_status('payload_writing', 'produce', 0, owned, loan, configuration)
                assert fixture.call('close', loan) == 0
                owned_wire = output(owned, 'payload_writing')
                body = json.loads(owned_wire)
                assert body['state'] == 'writing' and body['revision'] == '3'
                assert body['ownership_device'] == expected['ownership_device']
                assert body['ownership_inode'] == expected['ownership_inode']
                assert body['request_cid'] == reserved_body['request_cid']
                assert body['request_json'] == reserved_body['request_json']
                assert store.read(key) == StoredBytes(2, writing_wire)
                cases.append('exact_wide_ownership_is_prepared_without_a_durable_commit')
                assert_status('payload_writing', 'begin', 0, owned, configuration)
                assert_status('payload_writing', 'begin', -33, owned, configuration)
                write = ByteWrite(key, 2, owned_wire)
                store._connection.lose = True
                try:
                    store.compare_exchange_reserved(write, reservation)
                except OSError as error:
                    assert str(error) == 'Independent original Owned CAS acknowledgement loss'
                else:
                    raise AssertionError('Missing independent original Owned lost-ack case')
                assert store._connection.updates == 3
                assert_status('payload_writing', 'close', -9, owned)
                assert_status('payload_record', 'close', -9, record)
                assert_status('payload_request', 'close', -9, parent)
                assert fixture.call('close', original_input) == -9
                assert store.read_exchange(write) == StoredBytes(3, owned_wire)
                assert store._connection.updates == 3
                cases.append('lost_owned_cas_acknowledgement_keeps_original_custody_without_resend')
                observation = {**original, 'physical_revision': 3, 'record_json': owned_wire.decode()}
                for bad in ({**observation, 'physical_revision': 2},
                            {**observation, 'record_json': writing_wire.decode()},
                            {**observation, 'store_authority_cid': 'sha256:' + 'a' * 64}):
                    loan = copy(bad)
                    assert_status('payload_writing', 'confirm', -32, owned, loan, configuration)
                    assert fixture.call('close', loan) == 0
                loan = copy(observation)
                assert_status('payload_writing', 'confirm', -32, owned, loan, denied)
                assert_status('payload_writing', 'confirm', 0, owned, loan, configuration)
                assert_status('payload_writing', 'confirm', 0, owned, loan, configuration)
                assert fixture.call('close', loan) == 0
                assert store._connection.updates == 3
                cases.append('current_authority_and_exact_original_successor_resolve_pending_write')
                allocated = fixture.call('allocated')
                fixture.cleanup_ready = False
                assert_status('payload_writing', 'close', -9, owned)
                assert fixture.call('allocated') == allocated
                assert_status('payload_record', 'close', -9, record)
                fixture.cleanup_ready = True
                assert_status('payload_writing', 'close', 0, owned)
                assert fixture.call('allocated') == allocated - (2 * 65536 + expected['physical_copy_bytes'])
                assert_status('payload_writing', 'close', -2, owned)
                assert store.read_capacity(expected['capacity_namespace'], key) == reservation
                assert store.read(key) == StoredBytes(3, owned_wire)
                assert_status('payload_record', 'close', 0, record)
                assert_status('payload_request', 'close', 0, parent)
                assert fixture.call('close', original_input) == 0
                cases.append('cleanup_retry_preserves_original_disk_capacity_and_input_until_retirement')
    assert cases == expected['cases']
    return cases
