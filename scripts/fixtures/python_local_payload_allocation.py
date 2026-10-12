"""Unexecuted private ABI31 original allocation bytes and directory identity."""
import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from unittest.mock import patch

from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_storage import ByteFence, ByteWrite, LocalByteStore, StoredBytes


def check_payload_allocation(fixture, payload_loan, facts, configuration, denied,
                             copy, call, assert_status, new_output_ticket):
    expected = json.loads((Path(__file__).parent / 'python-local-payload-allocation.json').read_text())
    cases = []
    parent, original_input = payload_loan(facts)
    assert_status('payload_request', 'produce', 0, parent, configuration)
    record = call('payload_record', 'reserve', parent, new_output_ticket(), expected['physical_copy_bytes'])
    assert record > 0
    assert_status('payload_record', 'produce', 0, record, configuration)
    original = {'store_authority_cid': facts['store_authority_cid'],
                'material_generation_cid': facts['material_generation_cid']}

    def output(child, family):
        assert_status(family, 'validate', 0, child, configuration)
        size = call(family, 'length', child)
        assert 0 < size <= expected['max_record_bytes']
        return bytes(fixture.call('byte', child, index) for index in range(size))

    def record_confirm(family, child, revision, body):
        loan = copy({**original, 'physical_revision': revision, 'record_json': body.decode()})
        assert_status(family, 'confirm', 0, child, loan, configuration)
        assert fixture.call('close', loan) == 0

    class LostAllocationAck(sqlite3.Connection):
        writes = 0
        lose = False

        def execute(self, sql, *args, **kwargs):
            if sql.startswith(('INSERT INTO core_bytes', 'UPDATE core_bytes')):
                self.writes += 1
            result = super().execute(sql, *args, **kwargs)
            if sql == 'COMMIT' and self.lose:
                self.lose = False
                raise OSError('Independent original allocation ownership CAS acknowledgement lost')
            return result

    connect = sqlite3.connect
    with TemporaryDirectory(prefix='actql-abi31-original-allocation-') as directory:
        root_path = Path(directory) / 'private-files'
        root_path.mkdir(mode=0o700)
        files = LocalFileRoot(root_path, max_files=4, max_chunk_bytes=128)
        try:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=LostAllocationAck)):
                with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4,
                                    max_record_bytes=65536, max_payload_bytes=262144) as store:
                    key = facts['material_generation_cid']
                    initial = output(record, 'payload_record')
                    assert_status('payload_record', 'begin', 0, record, configuration)
                    assert store.compare_exchange(key, None, initial) == 0
                    record_confirm('payload_record', record, 0, initial)
                    assert_status('payload_allocation', 'reserve', -2, record, 1, 65300, expected['physical_copy_bytes'])
                    assert store.reserve_capacity(expected['capacity_namespace'], key,
                                                  facts['max_payload_bytes'], 1,
                                                  facts['max_payload_bytes'], 1)
                    capacity = store.read_capacity(expected['capacity_namespace'], key)
                    assert capacity is not None
                    reserved = call('payload_reservation', 'reserve', record, new_output_ticket(), expected['physical_copy_bytes'])
                    assert reserved > 0
                    observation = copy({**original, 'capacity_namespace': capacity.namespace,
                                        'reserved_bytes': capacity.reserved_bytes,
                                        'reserved_objects': capacity.reserved_objects})
                    assert_status('payload_reservation', 'produce', 0, reserved, observation, configuration)
                    assert fixture.call('close', observation) == 0
                    reserved_wire = output(reserved, 'payload_reservation')
                    assert_status('payload_reservation', 'begin', 0, reserved, configuration)
                    assert store.compare_exchange_reserved(ByteWrite(key, 0, reserved_wire), capacity) == 1
                    record_confirm('payload_reservation', reserved, 1, reserved_wire)
                    assert_status('payload_reservation', 'close', 0, reserved)
                    writing = call('payload_writing', 'reserve', record, 1, new_output_ticket(), expected['physical_copy_bytes'])
                    assert writing > 0
                    assert_status('payload_writing', 'produce', 0, writing, 0, configuration)
                    writing_wire = output(writing, 'payload_writing')
                    assert_status('payload_writing', 'begin', 0, writing, configuration)
                    assert store.compare_exchange_reserved(ByteWrite(key, 1, writing_wire), capacity) == 2
                    record_confirm('payload_writing', writing, 2, writing_wire)
                    assert_status('payload_writing', 'close', 0, writing)
                    original_fence = ByteFence(key, 2, writing_wire)
                    child = call('payload_allocation', 'reserve', record, 1, new_output_ticket(), expected['physical_copy_bytes'])
                    assert child > 0
                    assert_status('payload_allocation', 'reserve', -3, record, 2, 65300, expected['physical_copy_bytes'])
                    assert_status('payload_writing', 'reserve', -3, record, 2, 65300, expected['physical_copy_bytes'])
                    cases.append('original_writing_and_single_allocation_child_required')

                    absent = {**original, 'namespace': expected['allocation_namespace'],
                              'physical_revision': None, 'allocation_body': None}
                    for bad in ({k: v for k, v in absent.items() if k != 'allocation_body'},
                                {**absent, 'physical_revision': 0},
                                {**absent, 'physical_revision': '0'},
                                {**absent, 'extra': None}):
                        loan = copy(bad)
                        assert_status('payload_allocation', 'produce', -31, child, loan, configuration)
                        assert fixture.call('close', loan) == 0
                    for bad in ({**absent, 'namespace': expected['capacity_namespace']},
                                {**absent, 'store_authority_cid': 'sha256:' + 'a' * 64},
                                {**absent, 'material_generation_cid': 'sha256:' + 'a' * 64}):
                        loan = copy(bad)
                        assert_status('payload_allocation', 'produce', -32, child, loan, configuration)
                        assert fixture.call('close', loan) == 0
                    cases.append('closed_actual_store_observation_keeps_null_and_missing_distinct')
                    loan = copy(absent)
                    assert_status('payload_allocation', 'produce', -32, child, loan, denied)
                    assert_status('payload_allocation', 'produce', 0, child, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    envelope = json.loads(output(child, 'payload_allocation'))
                    assert sorted(envelope) == expected['envelope_fields']
                    assert envelope == {**original, 'namespace': expected['allocation_namespace'],
                                        'allocation_body': expected['allocation_name'],
                                        'expected_revision': None, 'previous_body': None}
                    allocation_key = store.namespaced_key(envelope['namespace'], envelope['material_generation_cid'])
                    assert store.read(allocation_key) is None
                    intent_write = ByteWrite(allocation_key, None, envelope['allocation_body'].encode())
                    assert_status('payload_allocation', 'begin', 0, child, configuration)
                    assert_status('payload_allocation', 'begin', -33, child, configuration)
                    assert store.compare_exchange_attached(intent_write, original_fence, capacity) == 0
                    intent = store.read_exchange(intent_write)
                    assert intent == StoredBytes(0, expected['allocation_name'].encode())
                    intent_fact = {**original, 'namespace': envelope['namespace'],
                                   'physical_revision': '0', 'allocation_body': intent.payload.decode()}
                    loan = copy(intent_fact)
                    assert_status('payload_allocation', 'confirm', 0, child, loan, configuration)
                    assert_status('payload_allocation', 'confirm', 0, child, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    assert_status('payload_allocation', 'close', 0, child)
                    assert store.read(key) == StoredBytes(2, writing_wire)
                    assert store.read_capacity(expected['capacity_namespace'], key) == capacity
                    cases.append('original_namespace_intent_cas_preserves_payload_and_capacity')

                    area = files.create_area(envelope['allocation_body'])
                    identity = files.observe_area(area)
                    owned = call('payload_allocation', 'reserve', record, 2, new_output_ticket(), expected['physical_copy_bytes'])
                    assert owned > 0
                    ownership = {**intent_fact, 'device': str(identity.device), 'inode': str(identity.inode)}
                    loan = copy(ownership)
                    assert_status('payload_allocation', 'produce', 0, owned, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    envelope = json.loads(output(owned, 'payload_allocation'))
                    assert envelope == {**original, 'namespace': expected['allocation_namespace'],
                                        'expected_revision': '0', 'previous_body': expected['allocation_name'],
                                        'allocation_body': expected['allocation_name'] + f'|{identity.device}|{identity.inode}'}
                    assert area.directory is None, 'Directory must not open before original ownership CAS'
                    assert store.read(key) == StoredBytes(2, writing_wire)
                    cases.append('exclusive_directory_identity_prepares_same_original_allocation')
                    owned_write = ByteWrite(allocation_key, 0, envelope['allocation_body'].encode())
                    assert_status('payload_allocation', 'begin', 0, owned, configuration)
                    assert_status('payload_allocation', 'begin', -33, owned, configuration)
                    store._connection.lose = True
                    try:
                        store.compare_exchange_attached(owned_write, original_fence, capacity)
                    except OSError as error:
                        assert str(error) == 'Independent original allocation ownership CAS acknowledgement lost'
                    else:
                        raise AssertionError('Missing independent original allocation lost ACK')
                    assert store._connection.writes == 5
                    assert_status('payload_allocation', 'close', -9, owned)
                    assert_status('payload_record', 'close', -9, record)
                    assert_status('payload_request', 'close', -9, parent)
                    assert fixture.call('close', original_input) == -9
                    actual = store.read_exchange(owned_write)
                    assert actual == StoredBytes(1, owned_write.payload)
                    assert store._connection.writes == 5
                    cases.append('lost_ownership_cas_ack_keeps_original_handle_without_resend')
                    fact = {**original, 'namespace': expected['allocation_namespace'],
                            'physical_revision': '1', 'allocation_body': actual.payload.decode()}
                    for bad in ({**fact, 'physical_revision': '2'},
                                {**fact, 'physical_revision': '0'},
                                {**fact, 'allocation_body': expected['allocation_name']},
                                {**fact, 'namespace': expected['capacity_namespace']}):
                        loan = copy(bad)
                        assert_status('payload_allocation', 'confirm', -32, owned, loan, configuration)
                        assert fixture.call('close', loan) == 0
                    loan = copy(fact)
                    assert_status('payload_allocation', 'confirm', -32, owned, loan, denied)
                    assert_status('payload_allocation', 'confirm', 0, owned, loan, configuration)
                    assert_status('payload_allocation', 'confirm', 0, owned, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    assert store._connection.writes == 5
                    cases.append('exact_current_observation_resolves_original_pending_write')
                    actual_directory = files.open_area(area)
                    assert actual_directory._identity == identity
                    assert files.close_area(area)
                    assert store.read(key) == StoredBytes(2, writing_wire)
                    assert store.read_capacity(expected['capacity_namespace'], key) == capacity
                    cases.append('confirmed_directory_opens_under_original_identity')
                    allocated = fixture.call('allocated')
                    fixture.cleanup_ready = False
                    assert_status('payload_allocation', 'close', -9, owned)
                    assert fixture.call('allocated') == allocated
                    assert_status('payload_record', 'close', -9, record)
                    fixture.cleanup_ready = True
                    assert_status('payload_allocation', 'close', 0, owned)
                    assert fixture.call('allocated') == allocated - (2 * 65536 + expected['physical_copy_bytes'])
                    assert_status('payload_allocation', 'close', -2, owned)
                    assert_status('payload_record', 'close', 0, record)
                    assert_status('payload_request', 'close', 0, parent)
                    assert fixture.call('close', original_input) == 0
                    cases.append('cleanup_failure_retains_allocation_child_and_source_borrow')
        finally:
            assert files.close(), 'Original test-owned physical file root cleanup remains pending'
    assert cases == expected['cases']
    return cases
