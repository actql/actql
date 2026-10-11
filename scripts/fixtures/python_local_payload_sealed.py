"""Prepared ABI32 actual file/Sealed CAS cases; unexecuted without a new module."""
import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from unittest.mock import patch

from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_storage import ByteFence, ByteWrite, LocalByteStore, StoredBytes


def check_payload_sealed(fixture, payload_loan, facts, configuration, denied,
                         copy, call, assert_status, new_output_ticket, names_observer=None):
    expected = json.loads((Path(__file__).parent / 'python-local-payload-sealed.json').read_text())
    independent = json.loads((Path(__file__).parent / 'python-local-result-storage-binding.json').read_text())
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

    def confirm(family, child, revision, body):
        loan = copy({**original, 'physical_revision': revision, 'record_json': body.decode()})
        assert_status(family, 'confirm', 0, child, loan, configuration)
        assert fixture.call('close', loan) == 0

    def produce(family, child, facts):
        loan = copy(facts)
        assert_status(family, 'produce', 0, child, loan, configuration)
        assert fixture.call('close', loan) == 0

    class LostSealedAck(sqlite3.Connection):
        writes = 0
        lose = False

        def execute(self, sql, *args, **kwargs):
            if sql.startswith(('INSERT INTO core_bytes', 'UPDATE core_bytes')):
                self.writes += 1
            result = super().execute(sql, *args, **kwargs)
            if sql == 'COMMIT' and self.lose:
                self.lose = False
                raise OSError('Independent original Sealed CAS acknowledgement lost')
            return result

    connect = sqlite3.connect
    with TemporaryDirectory(prefix='actql-abi32-original-sealed-') as directory:
        path = Path(directory)
        files_path = path / 'files'
        files_path.mkdir(mode=0o700)
        files = LocalFileRoot(files_path, max_files=4, max_chunk_bytes=5)
        physical = None
        child_files = None
        area = None
        try:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=LostSealedAck)):
                with LocalByteStore(path / 'core.sqlite', max_records=4,
                                    max_record_bytes=65536, max_payload_bytes=262144) as store:
                    key = facts['material_generation_cid']
                    initial = output(record, 'payload_record')
                    assert_status('payload_writing', 'reserve', -2, record, 3, 65200, expected['physical_copy_bytes'])
                    assert_status('payload_record', 'begin', 0, record, configuration)
                    assert store.compare_exchange(key, None, initial) == 0
                    confirm('payload_record', record, 0, initial)
                    assert store.reserve_capacity('publication_payload', key,
                                                  facts['max_payload_bytes'], 1,
                                                  facts['max_payload_bytes'], 1)
                    capacity = store.read_capacity('publication_payload', key)
                    assert capacity is not None
                    reserved = call('payload_reservation', 'reserve', record, new_output_ticket(), expected['physical_copy_bytes'])
                    assert reserved > 0
                    produce('payload_reservation', reserved,
                            {**original, 'capacity_namespace': capacity.namespace,
                             'reserved_bytes': capacity.reserved_bytes, 'reserved_objects': capacity.reserved_objects})
                    reserved_wire = output(reserved, 'payload_reservation')
                    assert_status('payload_reservation', 'begin', 0, reserved, configuration)
                    assert store.compare_exchange_reserved(ByteWrite(key, 0, reserved_wire), capacity) == 1
                    confirm('payload_reservation', reserved, 1, reserved_wire)
                    assert_status('payload_reservation', 'close', 0, reserved)
                    writing = call('payload_writing', 'reserve', record, 1, new_output_ticket(), expected['physical_copy_bytes'])
                    assert writing > 0
                    assert_status('payload_writing', 'produce', 0, writing, 0, configuration)
                    writing_wire = output(writing, 'payload_writing')
                    assert_status('payload_writing', 'begin', 0, writing, configuration)
                    assert store.compare_exchange_reserved(ByteWrite(key, 1, writing_wire), capacity) == 2
                    confirm('payload_writing', writing, 2, writing_wire)
                    if names_observer is not None:
                        names_observer.unowned(record)
                    assert_status('payload_writing', 'close', 0, writing)
                    assert_status('payload_writing', 'reserve', -2, record, 3, 65200, expected['physical_copy_bytes'])

                    # Original allocation intent and exclusive directory identity
                    # precede file creation, using the exact same Store/capacity.
                    allocation = call('payload_allocation', 'reserve', record, 1, new_output_ticket(), expected['physical_copy_bytes'])
                    assert allocation > 0
                    absent = {**original, 'namespace': 'publication_payload_allocation',
                              'physical_revision': None, 'allocation_body': None}
                    produce('payload_allocation', allocation, absent)
                    envelope = json.loads(output(allocation, 'payload_allocation'))
                    assert envelope['allocation_body'] == expected['allocation_name']
                    allocation_key = store.namespaced_key(envelope['namespace'], key)
                    intent = ByteWrite(allocation_key, None, envelope['allocation_body'].encode())
                    assert_status('payload_allocation', 'begin', 0, allocation, configuration)
                    assert store.compare_exchange_attached(intent, ByteFence(key, 2, writing_wire), capacity) == 0
                    intent_fact = {**original, 'namespace': envelope['namespace'],
                                   'physical_revision': '0', 'allocation_body': intent.payload.decode()}
                    loan = copy(intent_fact)
                    assert_status('payload_allocation', 'confirm', 0, allocation, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    assert_status('payload_allocation', 'close', 0, allocation)
                    area = files.create_area(envelope['allocation_body'])
                    identity = files.observe_area(area)
                    allocation = call('payload_allocation', 'reserve', record, 2, new_output_ticket(), expected['physical_copy_bytes'])
                    assert allocation > 0
                    produce('payload_allocation', allocation,
                            {**intent_fact, 'device': str(identity.device), 'inode': str(identity.inode)})
                    envelope = json.loads(output(allocation, 'payload_allocation'))
                    assert envelope['allocation_body'] == expected['allocation_name'] + f'|{identity.device}|{identity.inode}'
                    owned_area = ByteWrite(allocation_key, 0, envelope['allocation_body'].encode())
                    assert_status('payload_allocation', 'begin', 0, allocation, configuration)
                    assert store.compare_exchange_attached(owned_area, ByteFence(key, 2, writing_wire), capacity) == 1
                    loan = copy({**intent_fact, 'physical_revision': '1', 'allocation_body': owned_area.payload.decode()})
                    assert_status('payload_allocation', 'confirm', 0, allocation, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    assert_status('payload_allocation', 'close', 0, allocation)
                    child_files = files.open_area(area)
                    physical = child_files.create_writer('payload', facts['max_payload_bytes'])
                    file_identity = child_files.observe(physical).identity
                    owned = call('payload_writing', 'reserve', record, 2, new_output_ticket(), expected['physical_copy_bytes'])
                    assert owned > 0
                    produce('payload_writing', owned,
                            {**original, 'device': str(file_identity.device), 'inode': str(file_identity.inode)})
                    owned_wire = output(owned, 'payload_writing')
                    assert_status('payload_writing', 'begin', 0, owned, configuration)
                    assert store.compare_exchange_reserved(ByteWrite(key, 2, owned_wire), capacity) == 3
                    confirm('payload_writing', owned, 3, owned_wire)
                    assert_status('payload_writing', 'close', 0, owned)
                    cases.append('original_confirmed_area_and_file_ownership_precede_sealed')
                    if names_observer is not None:
                        names_observer.owned(record, owned_wire, files, child_files, physical)

                    physical_path = files_path / expected['allocation_name'] / 'payload'
                    if names_observer is not None and names_observer.staging is not None:
                        physical_path = files_path / names_observer.staging.expected['staging_name']
                    assert_status('payload_request', 'start_replay', 0, parent, configuration)
                    offset = 0
                    for _ in range(100):
                        chunk = call('payload_chunk', 'reserve', parent, new_output_ticket(), expected['physical_copy_bytes'])
                        assert chunk > 0
                        assert_status('payload_chunk', 'produce', 0, chunk, configuration)
                        assert_status('payload_chunk', 'validate', 0, chunk, configuration)
                        length = call('payload_chunk', 'length', chunk)
                        assert 0 <= length <= 65536
                        data = bytes(fixture.call('byte', chunk, index) for index in range(length))
                        final = call('payload_chunk', 'final', chunk)
                        assert final in (0, 1)
                        for at in range(0, length, 5):
                            part = data[at:at + 5]
                            assert physical.root.append(physical, offset, part) == len(part)
                            offset += len(part)
                        assert_status('payload_chunk', 'close', 0, chunk)
                        if final:
                            break
                    else:
                        raise AssertionError('Original payload replay did not terminate')
                    cursor = physical.root.begin_snapshot(physical)
                    for _ in range(100):
                        snapshot = physical.root.advance_snapshot(cursor)
                        if snapshot is not None:
                            break
                    else:
                        raise AssertionError('Original physical snapshot did not terminate')
                    assert snapshot.observation.identity == file_identity
                    assert snapshot.observation.size == independent['byte_count']
                    assert snapshot.physical_digest == 'sha256:' + independent['physical_sha256']
                    assert physical_path.read_bytes() == independent['payload'].encode()
                    assert fixture.queries == expected['source_queries']
                    cases.append('bounded_original_result_replay_and_file_digest_without_redispatch')
                    if names_observer is not None and names_observer.finalization is not None:
                        snapshot = names_observer.finalization.finish_physical(
                            names_observer, physical.root, physical, cursor)
                        physical_path = files_path / names_observer.finalization.expected['object_name']
                        assert physical_path.read_bytes() == independent['payload'].encode()

                    sealed = call('payload_writing', 'reserve', record, 3, new_output_ticket(), expected['physical_copy_bytes'])
                    assert sealed > 0
                    assert_status('payload_writing', 'reserve', -3, record, 3, 65200, expected['physical_copy_bytes'])
                    fact = {**original, 'device': str(file_identity.device), 'inode': str(file_identity.inode),
                            'size': str(snapshot.observation.size), 'physical_digest': snapshot.physical_digest}
                    assert_status('payload_writing', 'produce', -31, sealed, 0, configuration)
                    for bad in ({**fact, 'size': 12}, {**fact, 'size': None}, {**fact, 'size': '+12'},
                                {**fact, 'size': '012'}, {**fact, 'size': '-1'},
                                {**fact, 'size': '9223372036854775808'}, {**fact, 'extra': None},
                                {k: v for k, v in fact.items() if k != 'physical_digest'}):
                        loan = copy(bad)
                        assert_status('payload_writing', 'produce', -31, sealed, loan, configuration)
                        assert fixture.call('close', loan) == 0
                    for bad in ({**fact, 'device': str(file_identity.device + 1)},
                                {**fact, 'inode': str(file_identity.inode + 1)},
                                {**fact, 'size': str(facts['max_payload_bytes'] + 1)},
                                {**fact, 'physical_digest': 'invalid'},
                                {**fact, 'store_authority_cid': 'sha256:' + 'a' * 64},
                                {**fact, 'material_generation_cid': 'sha256:' + 'a' * 64}):
                        loan = copy(bad)
                        assert_status('payload_writing', 'produce', -32, sealed, loan, configuration)
                        assert fixture.call('close', loan) == 0
                    cases.append('closed_physical_observations_and_original_owner_refusals')
                    loan = copy(fact)
                    assert_status('payload_writing', 'produce', -32, sealed, loan, denied)
                    assert_status('payload_writing', 'produce', 0, sealed, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    sealed_wire = output(sealed, 'payload_writing')
                    body = json.loads(sealed_wire)
                    assert body['state'] == 'sealed' and body['revision'] == '4'
                    assert body['actual_bytes'] == str(independent['byte_count'])
                    assert body['ownership_device'] == body['device'] == fact['device']
                    assert body['ownership_inode'] == body['inode'] == fact['inode']
                    assert body['physical_digest'] == fact['physical_digest']
                    assert body['request_json'] == json.loads(owned_wire)['request_json']
                    assert store.read(key) == StoredBytes(3, owned_wire)
                    if names_observer is not None:
                        names_observer.candidate(record, owned_wire, sealed_wire)
                    cases.append('physical_sealed_candidate_keeps_original_writing_until_cas')
                    assert_status('payload_writing', 'begin', 0, sealed, configuration)
                    assert_status('payload_writing', 'begin', -33, sealed, configuration)
                    write = ByteWrite(key, 3, sealed_wire)
                    store._connection.lose = True
                    try:
                        store.compare_exchange_reserved(write, capacity)
                    except OSError as error:
                        assert str(error) == 'Independent original Sealed CAS acknowledgement lost'
                    else:
                        raise AssertionError('Missing original Sealed lost ACK')
                    assert store._connection.writes == expected['opaque_record_writes']
                    assert_status('payload_writing', 'close', -9, sealed)
                    assert_status('payload_record', 'close', -9, record)
                    assert_status('payload_request', 'close', -9, parent)
                    assert fixture.call('close', original_input) == -9
                    assert store.read_exchange(write) == StoredBytes(4, sealed_wire)
                    cases.append('lost_sealed_cas_ack_retains_original_custody_without_resend')
                    observation = {**original, 'physical_revision': 4, 'record_json': sealed_wire.decode()}
                    for bad in ({**observation, 'physical_revision': 5},
                                {**observation, 'record_json': owned_wire.decode()}):
                        loan = copy(bad)
                        assert_status('payload_writing', 'confirm', -32, sealed, loan, configuration)
                        assert fixture.call('close', loan) == 0
                    loan = copy(observation)
                    assert_status('payload_writing', 'confirm', -32, sealed, loan, denied)
                    assert_status('payload_writing', 'confirm', 0, sealed, loan, configuration)
                    assert_status('payload_writing', 'confirm', 0, sealed, loan, configuration)
                    assert fixture.call('close', loan) == 0
                    assert store._connection.writes == expected['opaque_record_writes']
                    assert store.read_capacity('publication_payload', key) == capacity
                    assert fixture.queries == expected['source_queries']
                    cases.append('exact_successor_and_current_authority_confirm_same_sealed_record')
                    if names_observer is not None and names_observer.finalization is not None:
                        names_observer.finalization.after_sealed(
                            names_observer, physical.root, record, sealed_wire, store, key, capacity, copy)
                    held = fixture.call('allocated')
                    fixture.cleanup_ready = False
                    assert_status('payload_writing', 'close', -9, sealed)
                    assert fixture.call('allocated') == held
                    fixture.cleanup_ready = True
                    assert_status('payload_writing', 'close', 0, sealed)
                    assert_status('payload_writing', 'close', -2, sealed)
                    assert_status('payload_writing', 'reserve', -2, record, 3, 65200, expected['physical_copy_bytes'])
                    assert_status('payload_record', 'close', 0, record)
                    assert_status('payload_request', 'close', 0, parent)
                    assert fixture.call('close', original_input) == 0
                    cases.append('pending_transport_cleanup_retries_same_handle_and_borrow')
                    assert physical.root.close_writer(physical)
                    physical = None
                    assert files.close_area(area)
                    area = None
                    assert store.read(key) == StoredBytes(4, sealed_wire)
                    assert store.read_capacity('publication_payload', key) == capacity
                    assert physical_path.read_bytes() == independent['payload'].encode()
                    cases.append('physical_close_preserves_named_bytes_and_durable_capacity')
        finally:
            if physical is not None:
                assert child_files is not None and physical.root.close_writer(physical)
            if area is not None:
                assert files.close_area(area)
            assert files.close(), 'Original physical cleanup remains pending'
    assert cases == expected['cases']
    return cases
