"""Prepared ABI33 names cases under the original ABI32 physical Sealed fixture.

These read-only loans cannot acquire a filename or grant Store publication.
Actual Sealed revision drift remains unexecuted until a matching module exists.
"""
import json
from pathlib import Path


class PayloadNameCases:
    def __init__(self, fixture, configuration, denied, call, assert_status, ticket, staging=None, finalization=None):
        self.fixture = fixture
        self.configuration = configuration
        self.denied = denied
        self.call = call
        self.status = assert_status
        self.ticket = ticket
        self.expected = json.loads((Path(__file__).parent / 'python-local-payload-names.json').read_text())
        self.cases = []
        self.child = None
        self.wire = None
        self.staging = staging
        self.finalization = finalization

    def unowned(self, record):
        self.status('payload_names', 'reserve', -2, record, self.ticket(),
                    self.expected['physical_copy_bytes'])
        self.cases.append('unowned_record_cannot_project_filesystem_names')

    def output(self):
        assert self.child is not None
        self.status('payload_names', 'validate', 0, self.child, self.configuration)
        size = self.call('payload_names', 'length', self.child)
        assert 0 < size <= self.expected['max_bytes']
        return bytes(self.fixture.call('byte', self.child, index) for index in range(size))

    def owned(self, record, original_wire, root, origin, physical):
        self.child = self.call('payload_names', 'reserve', record, self.ticket(),
                               self.expected['physical_copy_bytes'])
        assert self.child > 0, ('Original names reserve', self.child)
        self.status('payload_names', 'validate', -33, self.child, self.configuration)
        self.status('payload_names', 'produce', -32, self.child, self.denied)
        self.status('payload_names', 'produce', 0, self.child, self.configuration)
        self.wire = self.output()
        body = json.loads(self.wire)
        original = json.loads(original_wire)
        fields = ('staging_name', 'object_name', 'material_generation_cid',
                  'store_authority_cid', 'record_revision')
        assert set(body) == set(fields) | {'request_cid'}
        for field in fields:
            assert body[field] == self.expected[field], (field, body[field])
        assert body['request_cid'] == original['request_cid']
        assert body['record_revision'] == original['revision']
        self.cases.append('original_owned_names_are_closed_and_revision_bound')
        queries = self.fixture.queries
        self.status('payload_names', 'validate', -32, self.child, self.denied)
        self.status('payload_names', 'produce', -32, self.child, self.denied)
        self.status('payload_names', 'produce', 0, self.child, self.configuration)
        assert self.output() == self.wire
        assert self.fixture.queries == queries
        self.cases.append('cached_names_require_current_authority_without_redispatch')
        self.status('payload_names', 'reserve', -3, record, self.ticket(),
                    self.expected['physical_copy_bytes'])
        self.status('payload_names', 'reserve', -2, self.child, self.ticket(),
                    self.expected['physical_copy_bytes'])
        self.cases.append('duplicate_or_wrong_parent_cannot_acquire_another_projection')
        if self.staging is not None:
            self.staging.adopt(self, root, origin, physical, original_wire)

    def candidate(self, record, original_wire, candidate_wire):
        assert json.loads(original_wire)['revision'] == '3'
        assert json.loads(candidate_wire)['revision'] == '4'
        assert self.output() == self.wire
        self.cases.append('prepared_sealed_candidate_does_not_advance_original_names')
        held = self.fixture.call('allocated')
        self.fixture.cleanup_ready = False
        self.status('payload_names', 'close', -9, self.child)
        assert self.fixture.call('allocated') == held
        self.status('payload_names', 'validate', -5, self.child, self.configuration)
        self.cases.append('failed_cleanup_keeps_original_names_handle_and_allocation')
        self.fixture.cleanup_ready = True
        self.status('payload_names', 'close', 0, self.child)
        self.status('payload_names', 'close', -2, self.child)
        self.status('payload_names', 'validate', -2, self.child, self.configuration)
        assert self.fixture.call('allocated') < held
        self.cases.append('successful_same_handle_cleanup_rejects_reuse')

    def finish(self):
        assert self.cases == self.expected['cases']
        return self.cases
