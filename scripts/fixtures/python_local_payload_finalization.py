"""Prepared original Core name -> physical stopped final -> Sealed consumer."""
import errno
import json
import os
from pathlib import Path
from unittest.mock import patch


class PayloadFinalizationCases:
    def __init__(self, reader=None):
        self.expected = json.loads((Path(__file__).parent / 'python-local-payload-finalization.json').read_text())
        self.cases = []
        self.reader = reader
        self.cursor = None

    def finish_physical(self, names, root, physical, original_snapshot):
        body = json.loads(names.wire)
        assert body['object_name'] == self.expected['object_name']
        assert body['record_revision'] == '3'
        assert original_snapshot.result is not None
        original = original_snapshot.result
        assert original.observation.size == self.expected['byte_count']
        assert original.physical_digest == self.expected['physical_digest']
        names.status('payload_names', 'validate', 0, names.child, names.configuration)
        cursor = root.begin_finalization(physical, original_snapshot, body['object_name'])
        self.cursor = cursor
        slots = root._used_slots()
        queries = names.fixture.queries
        descriptor = physical.descriptor
        self.cases.append('original_owned_names_and_complete_bounded_snapshot_precede_final_io')
        close = os.close

        def lost_stop_acknowledgement(stopped):
            assert stopped == descriptor
            close(stopped)
            raise OSError(errno.EIO, 'Independent original writer stop acknowledgement lost')

        from actql_sdk._local_files import LocalFileError
        with patch('actql_sdk._local_files.os.close', side_effect=lost_stop_acknowledgement):
            try:
                root.advance_finalization(cursor)
            except LocalFileError as error:
                assert str(error) == 'Original Local writer physical stop remains unknown'
            else:
                raise AssertionError('Missing original physical stop uncertainty')
        assert physical.close_pending and physical.finalization is cursor
        assert not cursor.linked and cursor.result is None
        assert root._used_slots() == slots
        assert not root.close_finalization(cursor)
        try:
            os.fstat(descriptor)
        except OSError as error:
            assert error.errno == errno.EBADF
        else:
            raise AssertionError('Original writer did not physically stop')
        self.cases.append('lost_stop_ack_retains_original_cursor_slot_without_final_acquisition')
        names.status('payload_names', 'validate', -32, names.child, names.denied)
        with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Original writer stop repeated')):
            names.status('payload_names', 'validate', 0, names.child, names.configuration)
            actual = root.advance_finalization(cursor)
        assert physical.descriptor is None and cursor.stopped
        assert actual is original
        assert cursor.linked and cursor.source_removed
        assert physical.name == self.expected['object_name']
        assert names.fixture.queries == queries
        self.cases.append('same_actual_stop_observation_and_current_context_continue_original_final_work')
        with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('Original final link repeated')):
            assert root.advance_finalization(cursor) is original
        assert root._used_slots() == slots
        if self.reader is None:
            assert root.close_finalization(cursor)
        assert root._used_slots() == slots
        names.status('payload_names', 'validate', 0, names.child, names.configuration)
        assert names.output() == names.wire
        self.cases.append('final_physical_facts_keep_original_writing_record_and_store_reservation')
        return actual

    def after_sealed(self, names, root, record, sealed_wire, store, key, capacity, copy):
        if self.reader is not None:
            self.reader.consume_original(names, root, self.cursor, record, sealed_wire,
                                         store, key, capacity, copy)

    def finish(self):
        assert self.cases == self.expected['cases']
        return self.cases
