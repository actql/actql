"""Prepared original Core names -> physical stage consumer; not yet executed."""
import json
from pathlib import Path
from unittest.mock import patch


class PayloadStagingCases:
    def __init__(self):
        self.expected = json.loads((Path(__file__).parent / 'python-local-payload-staging.json').read_text())
        self.cases = []

    def adopt(self, names, root, origin, physical, original_wire):
        body = json.loads(names.wire)
        original = json.loads(original_wire)
        before = origin.observe(physical)
        assert body['staging_name'] == self.expected['staging_name']
        assert original['revision'] == body['record_revision'] == '3'
        assert original['ownership_device'] == str(before.identity.device)
        assert original['ownership_inode'] == str(before.identity.inode)
        assert before.size == 0
        # The nominal Core loan still checks the original current authority.
        names.status('payload_names', 'validate', 0, names.child, names.configuration)
        cursor = origin.begin_adoption(physical, root, body['staging_name'])
        self.cases.append('original_owned_record_and_core_name_precede_physical_link')
        slots = root._used_slots()
        queries = names.fixture.queries
        with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('Independent stage directory sync failure')):
            try:
                origin.advance_adoption(cursor)
            except OSError as error:
                assert str(error) == 'Independent stage directory sync failure'
            else:
                raise AssertionError('Missing original staging sync failure')
        assert cursor.linked and not cursor.source_removed and not cursor.complete
        assert physical.root is origin and physical.adoption is cursor
        assert root._used_slots() == slots
        self.cases.append('failed_directory_sync_retains_original_cursor_roots_and_slot')
        names.status('payload_names', 'validate', -32, names.child, names.denied)
        # Validation refusal is not a request to retry physical I/O. The same
        # original context must be authorized again before continuing cleanup.
        with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('Original link repeated')):
            names.status('payload_names', 'validate', 0, names.child, names.configuration)
            assert origin.advance_adoption(cursor) == before
        assert names.fixture.queries == queries
        self.cases.append('current_authority_rechecked_before_same_cursor_sync_retry')
        assert physical.root is root and physical.name == self.expected['staging_name']
        assert root.observe(physical) == before
        assert root._used_slots() == slots
        assert not origin._files
        assert root._files[id(physical)] is physical
        self.cases.append('exact_original_descriptor_moves_without_source_or_compute_replay')
        assert origin.close_adoption(cursor)
        try:
            origin.close_adoption(cursor)
        except ValueError:
            pass
        else:
            raise AssertionError('Retired physical staging cursor reused')
        names.status('payload_names', 'validate', 0, names.child, names.configuration)
        assert names.output() == names.wire
        self.cases.append('physical_cursor_retirement_does_not_advance_core_record')

    def finish(self):
        assert self.cases == self.expected['cases']
        return self.cases
