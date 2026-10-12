"""Unexecuted ABI43 regression for retained original ACK after parent close.

This fixture needs a matching fixed Wasm module. Syntax or compiler diagnostics
alone do not execute the case or establish public Local recovery.
"""
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from unittest.mock import patch

from actql_sdk._local_storage import ByteWrite, LocalByteStore, StoredBytes


def check_payload_parent_close(fixture, facts, configuration, denied, publication,
                               preflight, result, source, compute, copy, call,
                               assert_status, new_output_ticket):
    original_input = copy(facts)
    request = call('payload_request', 'reserve', publication, 0, original_input,
                   new_output_ticket(), 131300)
    assert request > 0
    assert_status('payload_request', 'produce', 0, request, configuration)
    record = call('payload_record', 'reserve', request, new_output_ticket(), 131300)
    assert record > 0
    assert_status('payload_record', 'produce', 0, record, configuration)
    size = call('payload_record', 'length', record)
    assert 0 < size <= 65536
    initial = bytes(fixture.call('byte', record, index) for index in range(size))
    original = {'store_authority_cid': facts['store_authority_cid'],
                'material_generation_cid': facts['material_generation_cid']}

    class LostInitialACK(sqlite3.Connection):
        writes = 0
        lose = False

        def execute(self, sql, *args, **kwargs):
            if sql.startswith('INSERT INTO core_bytes'):
                self.writes += 1
            result = super().execute(sql, *args, **kwargs)
            if sql == 'COMMIT' and self.lose:
                self.lose = False
                raise OSError('Original parent-close CAS acknowledgement loss')
            return result

    connect = sqlite3.connect
    with TemporaryDirectory(prefix='actql-abi43-parent-close-') as directory:
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *args, **kwargs: connect(
                       *args, **kwargs, factory=LostInitialACK)):
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4,
                                max_record_bytes=65536, max_payload_bytes=262144) as store:
                key = facts['material_generation_cid']
                write = ByteWrite(key, None, initial)
                assert_status('payload_record', 'begin', 0, record, configuration)
                store._connection.lose = True
                try:
                    store.compare_exchange(key, None, initial)
                except OSError as error:
                    assert str(error) == 'Original parent-close CAS acknowledgement loss'
                else:
                    raise AssertionError('Missing original lost acknowledgement')
                assert store.read_exchange(write) == StoredBytes(0, initial)
                assert store._connection.writes == 1
                for family, parent in [('publication', publication),
                                       ('publication_preflight', preflight),
                                       ('result', result), ('source_publication', source),
                                       ('compute', compute)]:
                    assert_status(family, 'close', -9, parent)
                assert_status('payload_record', 'close', -9, record)
                assert_status('payload_request', 'close', -9, request)
                assert fixture.call('close', original_input) == -9
                assert_status('payload_request', 'produce', -5, request, configuration)
                assert_status('payload_record', 'begin', -5, record, configuration)
                ack = {**original, 'physical_revision': 0, 'record_json': initial.decode()}
                foreign = copy({**ack, 'material_generation_cid': 'sha256:' + 'a' * 64})
                assert_status('payload_record', 'confirm', -32, record, foreign, configuration)
                assert fixture.call('close', foreign) == 0
                observation = copy(ack)
                assert_status('payload_record', 'confirm', -32, record, observation, denied)
                assert_status('payload_record', 'confirm', 0, record, observation, configuration)
                assert_status('payload_record', 'confirm', 0, record, observation, configuration)
                assert fixture.call('close', observation) == 0
                assert store._connection.writes == 1
                assert store.read_exchange(write) == StoredBytes(0, initial)
                assert_status('payload_record', 'close', 0, record)
                assert_status('payload_request', 'close', 0, request)
                assert fixture.call('close', original_input) == 0
    return ['pending_parent_close_keeps_exact_original_ack_current_and_no_resend']
