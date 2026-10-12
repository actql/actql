"""Prepared original final file -> bounded Core buffer/borrow consumer.

Physical digest and buffer retirement are not payload-value verification, Store
installation, current publisher authority or a public Result reader acceptance.
"""
import errno
import json
import os
from pathlib import Path
from unittest.mock import patch


class PayloadReaderCases:
    def __init__(self):
        self.expected = json.loads((Path(__file__).parent / 'python-local-payload-reader.json').read_text())
        self.cases = []

    def consume_original(self, names, root, final, record, sealed_wire, store, key, capacity, copy):
        from actql_sdk._local_storage import StoredBytes
        assert final is not None and final.result is not None
        assert store.read(key) == StoredBytes(4, sealed_wire)
        assert json.loads(sealed_wire)['state'] == 'sealed'
        current_names = names.call('payload_names', 'reserve', record, names.ticket(),
                                   names.expected['physical_copy_bytes'])
        assert current_names > 0
        reader = None
        try:
            names.status('payload_names', 'produce', -32, current_names, names.denied)
            names.status('payload_names', 'produce', 0, current_names, names.configuration)
            size = names.call('payload_names', 'length', current_names)
            assert 0 < size <= names.expected['max_bytes']
            projection = json.loads(bytes(names.fixture.call('byte', current_names, i) for i in range(size)))
            assert projection['record_revision'] == '4'
            assert projection['object_name'] == final.name == self.expected['object_name']
            assert projection['request_cid'] == json.loads(sealed_wire)['request_cid']
            assert final.result.observation.size == self.expected['byte_count']
            assert final.result.physical_digest == self.expected['physical_digest']
            names.status('payload_names', 'validate', 0, current_names, names.configuration)
            queries = names.fixture.queries
            slots = root._used_slots()
            reader = root.open_reader(final)
            assert root._used_slots() == slots + 1
            assert not root.close_finalization(final)
            self.cases.append('original_confirmed_sealed_names_and_current_context_precede_readonly_open')
            data = []
            offsets = []
            retained_original = False
            for _ in range(100):
                names.status('payload_names', 'validate', -32, current_names, names.denied)
                names.status('payload_names', 'validate', 0, current_names, names.configuration)
                chunk = root.read_reader(reader)
                assert len(chunk.data) <= self.expected['max_chunk_bytes']
                assert root.read_reader(reader) is chunk
                offsets.append(chunk.offset)
                loan = copy(chunk.data)
                borrow = names.fixture.call('borrow', loan)
                assert borrow > 0
                held = names.fixture.call('allocated')
                if not retained_original:
                    names.fixture.stop_ready = False
                    assert names.fixture.call('return', borrow) == -9
                    assert names.fixture.call('close', loan) == -9
                    assert names.fixture.call('allocated') == held
                    assert root.read_reader(reader) is chunk and reader.offset == chunk.offset
                    names.fixture.stop_ready = True
                    assert names.fixture.call('return', borrow) == 0
                    names.fixture.cleanup_ready = False
                    assert names.fixture.call('close', loan) == -9
                    assert names.fixture.call('allocated') == held
                    assert root.read_reader(reader) is chunk and reader.offset == chunk.offset
                    names.fixture.cleanup_ready = True
                    assert names.fixture.call('close', loan) == 0
                    retained_original = True
                else:
                    assert names.fixture.call('return', borrow) == 0
                    assert names.fixture.call('close', loan) == 0
                # The actual original Buffer Owner's stop and cleanup succeeded.
                # Only now release this same nominal physical chunk/offset.
                names.status('payload_names', 'validate', 0, current_names, names.configuration)
                root.release_reader_chunk(reader, chunk)
                data.append(chunk.data)
                if chunk.eof:
                    break
            else:
                raise AssertionError('Original bounded final reader did not terminate')
            assert offsets == self.expected['offsets']
            assert b''.join(data) == self.expected['payload'].encode()
            assert names.fixture.queries == queries
            self.cases.append('bounded_original_final_bytes_transfer_without_source_or_compute_replay')
            self.cases.append('same_chunk_retained_until_original_core_borrow_stop_and_buffer_cleanup')
            close = os.close

            def lose_ack(descriptor):
                close(descriptor)
                raise OSError(errno.EIO, 'Independent readonly stop acknowledgement lost')

            with patch('actql_sdk._local_files.os.close', side_effect=lose_ack):
                assert not root.finish_reader(reader)
            assert reader.finish_ready and reader.close_pending
            assert root._used_slots() == slots + 1
            assert not root.close_finalization(final)
            names.status('payload_names', 'validate', -32, current_names, names.denied)
            names.status('payload_names', 'validate', 0, current_names, names.configuration)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Readonly stop repeated')):
                assert root.finish_reader(reader)
            reader = None
            assert root._used_slots() == slots
            assert root.close_finalization(final)
            assert store.read(key) == StoredBytes(4, sealed_wire)
            assert store.read_capacity('publication_payload', key) == capacity
            assert names.fixture.queries == queries
            self.cases.append('physical_eof_and_same_handle_retirement_preserve_original_store_capacity')
        finally:
            if reader is not None:
                assert root.close_reader(reader), 'Original readonly physical cleanup remains pending'
            names.status('payload_names', 'close', 0, current_names)

    def finish(self):
        assert self.cases == self.expected['cases']
        return self.cases
