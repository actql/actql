"""Real private Native/Compute/Result boundary; no public or durable Run claim.

This diagnostic is deliberately unmetered, like existing positive preparation
fixtures. It does not prove execution within the product's default100M fuel.
Original metered counterexamples and their limits are unchanged.
"""
import hashlib
import json
from pathlib import Path
import sys

from python_local_physical import PhysicalFixture
from python_local_run_inputs import CONFIGURATION, REQUEST, encode
from python_local_publication_policy import publication_policy as frozen_publication_policy

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))
from actql_sdk._local_command import native_command
from actql_sdk._local_core import LocalCore, _PhysicalInput, _PublisherCallbacks
from actql_sdk._local_duckdb import DuckDBLibrary, DuckDBConnection, DuckDBTransferLimits


module_path, library_path, library_digest = sys.argv[1:4]
cleanup_only = sys.argv[4:] == ['--native-cleanup-only']
inventory_root = '--bounded-inventory-root' in sys.argv[4:]
source_publication = '--source-publication' in sys.argv[4:]
explicit_view = '--explicit-view' in sys.argv[4:]
final_publication = '--final-publication' in sys.argv[4:]
result_binding = '--result-binding' in sys.argv[4:]
commit_candidate = '--commit-candidate' in sys.argv[4:]
commit_materials = '--commit-materials' in sys.argv[4:]
commit_index_key = '--commit-index-key' in sys.argv[4:]
payload_request = '--payload-request' in sys.argv[4:]
payload_replay = '--payload-replay' in sys.argv[4:]
payload_record = '--payload-record' in sys.argv[4:]
payload_reservation = '--payload-reservation' in sys.argv[4:]
payload_writing = '--payload-writing' in sys.argv[4:]
payload_allocation = '--payload-allocation' in sys.argv[4:]
payload_sealed = '--payload-sealed' in sys.argv[4:]
payload_names = '--payload-names' in sys.argv[4:]
payload_staging = '--payload-staging' in sys.argv[4:]
payload_finalization = '--payload-finalization' in sys.argv[4:]
payload_reader = '--payload-reader' in sys.argv[4:]
payload_binding = '--payload-binding' in sys.argv[4:]
publisher_port = '--publisher-port' in sys.argv[4:]
assert sys.argv[4:] in ([], ['--native-cleanup-only'], ['--bounded-inventory-root'],
                       ['--bounded-inventory-root', '--source-publication'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--commit-materials'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--commit-materials', '--commit-index-key'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--publisher-port'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation', '--payload-sealed'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation', '--payload-sealed', '--payload-names'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation', '--payload-sealed', '--payload-names', '--payload-staging'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation', '--payload-sealed', '--payload-names', '--payload-staging', '--payload-finalization'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation', '--payload-sealed', '--payload-names', '--payload-staging', '--payload-finalization', '--payload-reader'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication', '--result-binding', '--commit-candidate', '--payload-request', '--payload-replay', '--payload-record', '--payload-reservation', '--payload-writing', '--payload-allocation', '--payload-sealed', '--payload-names', '--payload-staging', '--payload-finalization', '--payload-reader', '--payload-binding'])
source_cases = []
publication_cases = []
binding_cases = []
preflight_cases = []
preflight_retirement_cases = []
publication_retirement_cases = []
preflight_inputs = {}
preflight_output_tickets = {}
commit_cases = []
commit_material_cases = []
commit_index_key_cases = []
payload_request_cases = []
payload_replay_cases = []
payload_record_cases = []
payload_reservation_cases = []
payload_writing_cases = []
payload_allocation_cases = []
payload_sealed_cases = []
payload_names_cases = []
payload_staging_cases = []
payload_finalization_cases = []
payload_reader_cases = []
payload_binding_cases = []
publisher_cases = []
root = Path(__file__).resolve().parents[2]
module = Path(module_path).read_bytes()


class NativeFixture(PhysicalFixture):
    def __init__(self):
        self.connection = None
        self.view = None
        self.attempt = None
        self.workspace_ticket = 999
        self.queries = 0
        self.native_stop_ready = True
        self.native_cleanup_ready = True
        # Private independent authority fixture, not an installed product issuer.
        self.publisher_bridge = LocalCore.__new__(LocalCore)
        self.publisher_bridge._inputs = {}
        self.publisher_fence_ready = True
        self.publisher_answer = True
        self.publisher_revoke_after_auth = False
        self.publisher_seen = []
        super().__init__(module, 1001, capacity=8_388_608, slots=64,
                         fuel=None, execution_bytes=536_870_912,
                         retained_bytes=536_870_912 if inventory_root else 200_000_000)

    def native_settled(self, handle):
        assert handle == self.attempt and self.view is not None
        return 0 if self.view.committed else 1

    def native_stopped(self, handle):
        assert handle == self.attempt and self.connection is not None
        return 0 if self.native_stop_ready and self.connection.stop_new_io() else 1

    def native_cleaned(self, handle):
        assert handle == self.attempt and self.view is not None
        return 0 if self.native_cleanup_ready and self.view.close() else 1

    def publisher_current(self, ticket):
        return self.publisher_bridge._publisher_current(ticket)

    def publisher_begin(self, ticket, length):
        return self.publisher_bridge._publisher_begin(ticket, length)

    def publisher_byte(self, ticket, index, byte):
        return self.publisher_bridge._publisher_byte(ticket, index, byte)

    def publisher_finish(self, ticket):
        return self.publisher_bridge._publisher_finish(ticket)

    def stop(self, ticket, reader):
        if ticket == self.workspace_ticket:
            return 0 if self.connection.stop_new_io() else 1
        return super().stop(ticket, reader)

    def cleanup(self, ticket):
        if ticket == self.workspace_ticket:
            return 0 if self.connection.close() else 1
        return super().cleanup(ticket)


fixture = NativeFixture()
ticket = 0
projection_inputs = {}


def copy(value):
    global ticket
    ticket += 1
    payload = value if isinstance(value, bytes) else encode(value)
    return fixture.copy(ticket, payload, sys.getsizeof(payload))


def call(family, name, *args):
    result = fixture.exports['actql_' + family + '_' + name](fixture.store, fixture.nonce, *args)
    # These fixture inputs are distinct from the semantic child and its borrow.
    # Only the original Owner's successful close permits retiring the input.
    input_position = {
        ('source_publication', 'reserve'): 1,
        ('publication', 'reserve'): 1,
        ('run', 'install_configuration'): 0,
    }.get((family, name))
    if input_position is not None and result > 0:
        projection_inputs[(family, result)] = args[input_position]
    if (name == 'close' and family in ('source_publication', 'publication') or
            family == 'run' and name == 'close_configuration') and result == 0:
        input_handle = projection_inputs.get((family, args[0]))
        if input_handle is not None:
            status = fixture.call('close', input_handle)
            assert status == 0, ('Fixture input cleanup after original Owner close',
                                 family, args[0], input_handle, status)
            del projection_inputs[(family, args[0])]
    return result


def assert_status(family, name, expected, *args):
    actual = call(family, name, *args)
    assert actual == expected, (family, name, 'expected', expected, 'actual', actual)


def publication_policy():
    return frozen_publication_policy(root)


def projection(family, reserve, produce, length, close, *args):
    global ticket
    ticket += 1
    handle = call(family, reserve, *args, ticket, 2_097_200)
    assert handle > 0
    assert call(family, produce, handle) == 0
    size = call(family, length, handle)
    assert 0 <= size <= 1_048_576
    wire = bytes(fixture.call('byte', handle, index) for index in range(size))
    fixture.inputs[ticket] = b''
    assert call(family, close, handle) == 0
    return wire


def contracts():
    aoa = json.loads((root / 'spec/contracts/actql-aoa.json').read_text())
    return {
        'registry': (root / aoa['pipeline_registry_file']).read_text(),
        'values': encode(aoa['execution_contracts']['REL.values']).decode(),
        'fragment': encode(aoa['execution_contracts']['ACTQL.expression_fragment/0.1']).decode(),
        'ordered': encode(aoa['execution_contracts']['REL.derive.ordered']).decode(),
    }


account = encode({'version': 'actql-execution-account-config/0.1',
                 'account_id': 'local-account', 'entries': [{
                     'entry_id': 'local-fixture', 'outcome': 'allow',
                     'principal': {'all': True}, 'connection': {'all': True},
                     'resource': {'all': True}, 'operation': {'all': True},
                     'exclusions': []}]}).decode()
read_account = {'read_account': account}


def command(kind):
    wire = projection('source', 'reserve_command', 'produce_command',
                      'command_length', 'close_command', fixture.attempt, kind,
                      copy(read_account))
    return native_command(wire)


def stream_rows(command_value):
    stream = fixture.connection.prepare(command_value.sql, DuckDBTransferLimits(),
                                        parameters=command_value.parameters)
    fixture.queries += 1
    stream.execute()
    destination = bytearray(1_048_576)
    fields = bytes(destination[:stream.write_fields(destination)]).decode()
    columns = [[] for _ in json.loads(fields)]
    count = 0
    while (size := stream.read_column_row(destination)) is not None:
        row = json.loads(bytes(destination[:size]))
        for target, scalar in zip(columns, row, strict=True):
            target.extend(scalar)
        count += 1
    assert stream.close()
    return fields, count, columns


def event(kind, **values):
    assert call('source', 'accept', fixture.attempt, kind, copy({**read_account, **values})) == 0
    assert call('source', 'close_event', fixture.attempt) == 0


try:
    assert fixture.exports['actql_host_abi_version'](fixture.store) == 38
    fixture.stop_ready = fixture.cleanup_ready = True
    workspace = fixture.exports['actql_workspace_reserve'](
        fixture.store, fixture.nonce, fixture.workspace_ticket, 67_108_864)
    assert workspace > 0
    library = DuckDBLibrary(Path(library_path), digest=library_digest, version='v1.5.5')
    fixture.connection = DuckDBConnection(library, ':memory:', memory_bytes=67_108_864,
                                         readonly=False)
    for sql in ('CREATE TABLE records(id DOUBLE, amount DOUBLE)',
                'INSERT INTO records VALUES (3, NULL), (1, NULL), (2, NULL)'):
        setup = fixture.connection.prepare(sql, DuckDBTransferLimits())
        setup.execute()
        destination = bytearray(1024)
        while setup.read_row(destination) is not None:
            pass
        assert setup.close()
    environment_wire = (root / 'scripts/fixtures/python-local-native-environment.json').read_text().strip()
    publication = {'environmentCid': 'sha256:535c4c9bbefc918c4e1c67afcc8a7fae402d37b9113d039b3a03c758ae59a58e',
                   'aliases': [{'name': 'records', 'sourceRef': 'connector://crm/main/r#v',
                                'sourceViewContractCid': 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
                                'schemaContractCid': 'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4'}], 'tableWrites': []}
    environment = call('program', 'install_source_environment', copy({
        'environment': environment_wire, 'publication': encode(publication).decode()}))
    assert environment > 0
    program = {'version': 'actql/0.1', 'id': 'python-native-explicit-publication' if explicit_view else 'python-native-result', 'stages': [
        {'id': 'acquire', 'inputs': {'remote': {'connector': 'crm/main', 'resource': 'r',
                                             **({'view': 'v'} if explicit_view else {})}},
         'steps': [{'filter': 'id > 2', 'as': 'filtered'}, {'select': ['id'], 'as': 'selected'}],
         'results': {'out': {'from': 'selected', 'fields': ['id']}}},
        {'id': 'compute', 'inputs': {'r': {'result': {'stage': 'acquire', 'result': 'out'}}},
         'steps': [{'derive': {'value': 'id + 1'}, 'as': 'derived'}, {'select': ['value'], 'as': 'selected'}],
         'results': {'out': {'from': 'selected', 'fields': ['value']}}},
        {'id': 'final', 'inputs': {'r': {'result': {'stage': 'compute', 'result': 'out'}}},
         'steps': [{'derive': {'next': 'value + 1'}, 'as': 'derived'}, {'select': ['next'], 'as': 'selected'}],
         'results': {'out': {'from': 'selected', 'fields': ['next']}}}],
        'results': {'answer': {'from': {'stage': 'final', 'result': 'out'}}}}
    if final_publication:
        program['meta'] = {'note': 'original', 'nested': {'meta': 'presentation'}}
    preparation = call('program', 'reserve_preparation', environment, copy(program), 1)
    assert preparation > 0 and call('program', 'prepare', preparation) == 0
    assert call('program', 'prepared_results', preparation) == 1
    configuration = call('run', 'install_configuration', copy({**CONFIGURATION, 'account': account}))
    assert configuration > 0
    run = call('run', 'reserve', configuration, preparation, copy(REQUEST))
    assert run > 0 and call('run', 'prepare', run) == 0 and call('run', 'prepared', run) == 0
    if source_publication:
        # These are distinct authored Programs, before checking or capture.
        # Never rewrite the original sole-view input to claim its audit passed.
        ticket += 1
        refused_journal = call('material', 'reserve', run, 5, ticket, 2_097_200)
        assert refused_journal > 0
        fixture.inputs[ticket] = b''
        if explicit_view:
            assert call('material', 'produce', refused_journal) == 0
            length = call('material', 'length', refused_journal)
            assert 0 < length <= 1_048_576
            wire = bytes(fixture.call('byte', refused_journal, index) for index in range(length))
            frozen = json.loads((root / 'spec/contracts/actql-effect-free-local-completion-free-fixture.json').read_text())
            expected_journal = json.loads(frozen['journal_preimage'])
            expected_journal['journal_cid'] = frozen['journal_cid']
            assert wire == json.dumps(expected_journal, sort_keys=True, separators=(',', ':')).encode()
            assert call('material', 'produce', refused_journal) == 0
        else:
            assert call('material', 'produce', refused_journal) == -34
            assert call('material', 'length', refused_journal) == -33
            assert call('material', 'produce', refused_journal) == -33
        assert call('material', 'close', refused_journal) == 0
        assert fixture.queries == 0, 'Normalization audit cannot fetch Source'
    request = projection('material', 'reserve', 'produce', 'length', 'close', run, 2).decode()
    definition = projection('material', 'reserve', 'produce', 'length', 'close', run, 3).decode()
    start = call('run', 'reserve_physical_start', run, configuration, copy({
        'request': request, 'definition_cid': definition, 'reserved': True,
        'physically_unstarted': True, 'cancellation_requested': False, 'pre_start_failure_confirmed': False}))
    assert start > 0 and call('run', 'confirm_physical_start', start) == 0
    bodies = contracts()
    source = call('source', 'reserve_configuration', run, copy({
        'stage': 0, 'source_index': 0, **bodies, 'database_schema': 'main', 'table': 'records',
        'query_contract': (root / 'spec/contracts/actql-query-acquisition.json').read_text(),
        'evidence_contract': (root / 'spec/contracts/actql-query-process-evidence.json').read_text(),
        'two_receipt_contract': (root / 'spec/contracts/actql-query-two-receipt.json').read_text(),
        'read_account': account, 'read_principal': 'local-user', 'read_connection': 'python.local',
        'read_resource': 'records', 'read_operation': 'read', 'read_context_cid': CONFIGURATION['context_cid']}))
    assert source > 0 and call('source', 'configure', source) == 0
    configured = call('source', 'configured', source)
    assert configured == 0, ('Original typed Source construction failure', call('source', 'configuration_issue', source))
    inventory = [call('source', 'capacity', source, field) for field in range(3)]
    assert 200_000_000 < inventory[0] <= 536_870_912
    assert inventory[1] == 536_870_912 and inventory[2] >= 3_000_000
    assert fixture.queries == 0, 'Capacity planning must not fetch Source'
    fixture.attempt = call('source', 'reserve_attempt', source, start, copy({
        **read_account, 'attempt_nonce': 'native-result-private-fixture'}))
    assert fixture.attempt > 0 and call('source', 'start', fixture.attempt) == 0
    assert call('source', 'started', fixture.attempt) == 0
    fixture.view = fixture.connection.begin_read_view()
    if source_publication:
        # Command reservation is permitted only while acquisition is active.
        # An unproduced, capacity-refused command still owns its physical ticket.
        command_input = copy(read_account)
        ticket += 1
        collision_ticket = ticket
        fixture.inputs[collision_ticket] = b''
        refused_command = call('source', 'reserve_command', fixture.attempt, 1,
                               command_input, collision_ticket, 9000000)
        assert refused_command > 0, 'Refused reservation still owns its cleanup ticket'
        assert call('source', 'produce_command', refused_command) == -4
    fields, rows, columns = stream_rows(command(1))
    event(1, fields=fields, rows=rows, columns=encode(columns).decode())
    for kind, receipt in ((2, 2), (3, 3)):
        fields, rows, columns = stream_rows(command(kind))
        event(receipt, fields=fields)
        event(4, rows=rows, columns=encode(columns).decode())
        event(5)
    fixture.view.commit()
    event(6)
    assert call('source', 'completed', fixture.attempt) == 0
    assert fixture.queries == 3, 'One original metadata/validation/query sequence only'
    if cleanup_only:
        # Closing the pool seals new admission, but cannot erase a live
        # Native reservation before physical stop and cleanup are observed.
        assert fixture.call('close_pool') == -9
    else:
        compute = call('compute', 'reserve', fixture.attempt, copy({**read_account, **bodies}))
        assert compute > 0 and call('compute', 'configure', compute) == 0
        assert call('compute', 'configured', compute) == 0
        def source_loan(max_work=1000000, **changes):
            global ticket
            request_input = copy({'observed_at': '2026-10-10T00:00:01.000Z',
                                  'capture_started_at': '2026-10-10T00:00:00.000Z',
                                  'capture_completed_at': '2026-10-10T00:00:01.000Z',
                                  'max_work': max_work, 'max_workspace_slots': 1000000, **changes})
            ticket += 1
            output_ticket = ticket
            fixture.inputs[output_ticket] = b''
            handle = call('source_publication', 'reserve', compute, request_input,
                          output_ticket, 131200)
            assert handle > 0
            return handle

        if source_publication:
            collision_input = copy({'observed_at': '2026-10-10T00:00:01.000Z',
                                      'capture_started_at': '2026-10-10T00:00:00.000Z',
                                      'capture_completed_at': '2026-10-10T00:00:01.000Z',
                                    'max_work': 1000000, 'max_workspace_slots': 1000000})
            assert call('source_publication', 'reserve', compute, collision_input,
                        collision_ticket, 131200) == -3
            assert call('source', 'close_command', refused_command) == 0
            source_cases.append('source_projection_rejects_pending_command_ticket')
            malformed = source_loan(observed_at=None)
            assert call('source_publication', 'prepare', malformed, configuration) == -31
            assert call('source_publication', 'close', malformed) == 0
            source_cases.append('source_request_null_is_not_absent')
            for field in ('capture_started_at', 'capture_completed_at'):
                malformed = source_loan(**{field: None})
                assert call('source_publication', 'prepare', malformed, configuration) == -31
                assert call('source_publication', 'length', malformed) == -33
                assert call('source_publication', 'close', malformed) == 0
                source_cases.append(field + '_null_refused_before_issuance')
            abandoned = source_loan()
            assert call('source_publication', 'prepare', abandoned, configuration) == 0
            assert call('source_publication', 'finish', abandoned, configuration) == -7
            assert call('source_publication', 'advance', abandoned, 1) == 0
            assert call('source_publication', 'progress', abandoned, 2) == 1
            assert call('source_publication', 'close', abandoned) == 0
            assert call('compute', 'configured', compute) == 0
            source_cases.append('source_unfinished_cancel_keeps_original_capture')
            exhausted = source_loan(max_work=1)
            assert call('source_publication', 'prepare', exhausted, configuration) == 0
            assert call('source_publication', 'advance', exhausted, 1) == 0
            assert call('source_publication', 'advance', exhausted, 1) == -32
            assert call('source_publication', 'progress', exhausted, 2) == 1
            assert call('source_publication', 'close', exhausted) == 0
            source_cases.append('source_budget_exhaustion_keeps_monotone_work')
            denied_account = json.loads(account)
            denied_account['entries'][0]['outcome'] = 'deny'
            denied_configuration = call('run', 'install_configuration', copy({
                **CONFIGURATION, 'account': encode(denied_account).decode()}))
            assert denied_configuration > 0
            revoked = source_loan()
            assert call('source_publication', 'prepare', revoked, configuration) == 0
            for _ in range(10000):
                assert call('source_publication', 'advance', revoked, 7) == 0
                if call('source_publication', 'progress', revoked, 0) == 1:
                    break
            else:
                raise AssertionError('Source identity did not complete within the fixture bound')
            assert call('source_publication', 'finish', revoked, denied_configuration) == -32
            assert call('source_publication', 'length', revoked) == -33
            assert call('source_publication', 'close', revoked) == 0
            assert call('run', 'close_configuration', denied_configuration) == 0
            source_cases.append('source_revocation_before_issuance_refused')
            expected_work = None
            expected_body = None
            for quantum in (1, 7, 100):
                source_output = source_loan()
                assert call('source_publication', 'prepare', source_output, configuration) == 0
                spent = 0
                for _ in range(10000):
                    assert call('source_publication', 'advance', source_output, quantum) == 0
                    work = call('source_publication', 'progress', source_output, 1)
                    assert 0 <= work <= quantum
                    spent += work
                    if call('source_publication', 'progress', source_output, 0) == 1:
                        break
                else:
                    raise AssertionError('Source identity did not complete within the fixture bound')
                assert call('source_publication', 'progress', source_output, 2) == spent
                if expected_work is None:
                    expected_work = spent
                assert spent == expected_work
                assert call('source_publication', 'finish', source_output, configuration) == 0
                length = call('source_publication', 'length', source_output)
                assert 0 < length <= 65536
                wire = bytes(fixture.call('byte', source_output, index) for index in range(length))
                body = json.loads(wire)
                assert set(body) == {'logical', 'evidence', 'observation', 'invocation'}
                logical, evidence = json.loads(body['logical']), json.loads(body['evidence'])
                observation = json.loads(body['observation'])
                invocation = json.loads(body['invocation'])
                assert observation['version'] == 'actql-observation-set/0.1'
                assert observation['source_evidence_cids'] == [evidence['source_evidence_cid']]
                assert observation['captured_input_artifact_cids'] == []
                assert observation['capture_started_at'] == '2026-10-10T00:00:00.000Z'
                assert observation['capture_completed_at'] == '2026-10-10T00:00:01.000Z'
                assert observation['data_policy_cid'] == evidence['effective_data_policy_cid']
                assert invocation['version'] == 'actql-run-invocation/0.1'
                assert invocation['observation_set_cid'] == observation['observation_set_cid']
                assert invocation['invocation_template_cid'] == observation['invocation_template_cid']
                assert logical['version'] == 'actql-source-input-logical/0.1'
                # Independent registered preimage for the checked acquire stage:
                # {"sort":"relation","value":[{"id":3}]} (filter, then select).
                assert logical['logical_relation_cid'] == (
                    'sha256:571faa1e5e1447b632772f94003f0e079c7157e175331a568f6ceecf50b75dfc')
                assert evidence['version'] == 'actql-source-evidence/0.1'
                assert logical['completeness'] == evidence['completeness'] == 'complete'
                assert evidence['source_ref'] == 'connector://crm/main/r#v'
                assert evidence['input_logical_cid'] == logical['input_logical_cid']
                assert evidence['authority_scope_cid'] == CONFIGURATION['authority_scope_cid']
                assert evidence['observed_at'] == '2026-10-10T00:00:01.000Z'
                assert evidence['source_data_policy_cid'] == evidence['effective_data_policy_cid'] == (
                    'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf')
                if expected_body is None:
                    expected_body = body
                assert body == expected_body, 'Quantum cannot change existing Owner identity'
                fixture.cleanup_ready = False
                assert call('source_publication', 'close', source_output) == -9
                fixture.cleanup_ready = True
                assert call('source_publication', 'close', source_output) == 0
                assert fixture.queries == 3, 'Identity issuance must not reacquire Source'
                source_cases.append('source_quantum_' + str(quantum) + '_identity_and_cleanup')
        source_pin = source_loan()
        assert call('source_publication', 'prepare', source_pin, configuration) == 0
        assert call('source_publication', 'advance', source_pin, 1) == 0
        for _ in range(10000):
            assert call('source_publication', 'advance', source_pin, 100) == 0
            if call('source_publication', 'progress', source_pin, 0) == 1:
                break
        else:
            raise AssertionError('Original Source invocation did not complete')
        assert call('source_publication', 'finish', source_pin, configuration) == 0
        intent_facts = json.loads((root / 'scripts/fixtures/python-local-publication-intent.json').read_text())
        _, retention_wire = publication_policy()

        def preflight_loan(**changes):
            global ticket
            input_handle = copy({**intent_facts, 'retentions': [retention_wire], **changes})
            ticket += 1
            fixture.inputs[ticket] = b''
            handle = call('publication_preflight', 'reserve', source_pin, input_handle, ticket, 2097200)
            assert handle > 0
            preflight_inputs[handle] = input_handle
            preflight_output_tickets[handle] = ticket
            return handle

        # Task reservation alone invokes no operation; the original preflight
        # is required before the existing activation Owner can be called.
        premature = call('task', 'reserve', compute, configuration)
        assert premature > 0
        assert_status('task', 'start', -36, premature)
        assert_status('task', 'started', -33, premature)
        assert_status('task', 'close', 0, premature)
        preflight_cases.append('task_activation_requires_original_preflight')
        for changes, status in (({'retentions': None}, -31), ({'retentions': []}, -31),
                                ({'external_idempotency_key': None}, -31),
                                ({'retentions': [retention_wire, retention_wire]}, -32)):
            malformed = preflight_loan(**changes)
            assert_status('publication_preflight', 'prepare', status, malformed, configuration)
            assert_status('publication_preflight', 'length', -33, malformed)
            assert_status('publication_preflight', 'close', 0, malformed)
        foreign_retention = json.loads(publication_policy()[0]['retention_preimage'])
        foreign_retention['effective_data_policy_cid'] = 'sha256:' + '8' * 64
        foreign_retention['effective_retention_policy_cid'] = 'sha256:' + hashlib.sha256(encode(foreign_retention)).hexdigest()
        malformed = preflight_loan(retentions=[encode(foreign_retention).decode()])
        assert_status('publication_preflight', 'prepare', -32, malformed, configuration)
        assert_status('publication_preflight', 'close', 0, malformed)
        preflight_cases.append('closed_original_policy_and_complete_inventory')
        denied_account = json.loads(account)
        denied_account['entries'][0]['outcome'] = 'deny'
        denied_preflight_configuration = call('run', 'install_configuration', copy({
            **CONFIGURATION, 'account': encode(denied_account).decode()}))
        denied = preflight_loan()
        assert_status('publication_preflight', 'prepare', -32, denied, denied_preflight_configuration)
        assert_status('publication_preflight', 'prepare', -33, denied, configuration)
        assert_status('publication_preflight', 'close', 0, denied)
        preflight = preflight_loan()
        assert_status('publication_preflight', 'retire_output', -33, preflight)
        assert fixture.cleanups.get(preflight_output_tickets[preflight], 0) == 0
        assert_status('publication_preflight', 'prepare', 0, preflight, configuration)
        assert_status('publication_preflight', 'prepare', -32, preflight, denied_preflight_configuration)
        assert_status('publication_preflight', 'prepare', 0, preflight, configuration)
        preflight_size = call('publication_preflight', 'length', preflight)
        assert 0 < preflight_size <= 1048576
        preflight_body = json.loads(bytes(fixture.call('byte', preflight, i) for i in range(preflight_size)))
        assert set(preflight_body) == {'request', 'attempt'}
        original_request = json.loads(preflight_body['request'])
        original_attempt = json.loads(preflight_body['attempt'])
        assert original_request['namespace_id'] == intent_facts['namespace_id']
        assert original_request['publication_policy_cid'] == intent_facts['publication_policy_cid']
        assert original_request['publication_target_cid'] == intent_facts['publication_target_cid']
        assert original_request['authority_scope_cid'] == CONFIGURATION['authority_scope_cid']
        assert [r['result_name'] for r in original_request['inventory']] == ['answer']
        assert original_attempt['fence_cid'] == intent_facts['fence_cid']
        assert original_attempt['attempt_id'] == intent_facts['attempt_id']
        assert 'external_idempotency_key' not in original_attempt
        assert call('run', 'close_configuration', denied_preflight_configuration) == 0
        assert fixture.queries == 3
        preflight_cases.append('original_intent_current_access_and_no_source_reexecution')
        # Retire only the already copied transport output. The original
        # preflight, Source pin and input borrow remain for task/publication use.
        allocated_before_retire = fixture.call('allocated')
        fixture.cleanup_ready = False
        assert_status('publication_preflight', 'retire_output', -9, preflight)
        assert fixture.call('allocated') == allocated_before_retire
        assert fixture.call('close', preflight_inputs[preflight]) == -9
        fixture.cleanup_ready = True
        assert_status('publication_preflight', 'retire_output', 0, preflight)
        assert fixture.call('allocated') == allocated_before_retire - 4194352
        assert_status('publication_preflight', 'retire_output', 0, preflight)
        assert fixture.cleanups[preflight_output_tickets[preflight]] == 2
        assert_status('publication_preflight', 'length', -33, preflight)
        assert fixture.call('byte', preflight, 0) == -2
        assert_status('publication_preflight', 'prepare', 0, preflight, configuration)
        assert fixture.call('close', preflight_inputs[preflight]) == -9
        assert fixture.queries == 3
        preflight_retirement_cases.extend([
            'unfinished_projection_cannot_retire_semantic_custody',
            'same_output_cleanup_retry_releases_only_exact_allocation',
            'retired_output_refuses_reads_and_keeps_original_input_borrow'])
        tasks = []
        for _ in range(2):
            task = call('task', 'reserve', compute, configuration)
            assert task > 0 and call('task', 'start', task) == 0
            started = call('task', 'started', task)
            assert started == 0, ('Original typed task failure', _,
                                  call('task', 'issue', task),
                                  [call('task', 'assessment', task, 0, field) for field in range(8)])
            for _ in range(1000):
                fed = call('task', 'feed', task, 1)
                assert fed == 0, ('Original typed input feeding failure', fed, call('task', 'issue', task))
                if call('task', 'inputs_ready', task) == 0:
                    break
            else:
                raise AssertionError('Input feeding did not complete within the fixture bound')
            for _ in range(1000):
                assert call('task', 'advance', task, 1) == 0
                if call('task', 'progress', task, 0) == 1:
                    break
            else:
                raise AssertionError('Compute did not complete within the fixture bound')
            assert call('task', 'prepare_finalization', task) == 0
            assert call('task', 'complete', task) == -7, 'Execution completion is not finalization'
            for _ in range(1000):
                assert call('task', 'advance_finalization', task, 1) == 0
                if call('task', 'progress', task, 0) == 1:
                    break
            else:
                raise AssertionError('Finalization did not complete within the fixture bound')
            assert call('task', 'complete', task) == 0
            tasks.append(task)
        assert call('result', 'reserve', tasks[0], 0) == -2, 'Named Result belongs to the checked final producer'
        result = call('result', 'reserve', tasks[1], 0)
        assert result > 0 and call('result', 'start', result) == 0
        for _ in range(1000):
            assert call('result', 'feed', result, 1) == 0
            if call('result', 'inputs_ready', result) == 0:
                break
        else:
            raise AssertionError('Result bridge did not finish within the fixture bound')
        assert call('result', 'finish_preparation', result) == -7
        for _ in range(1000):
            assert call('result', 'advance', result, 1) == 0
            if call('result', 'progress', result, 0) == 1:
                break
        else:
            raise AssertionError('Result preparation did not finish within the fixture bound')
        assert call('result', 'finish_preparation', result) == 0
        chunks = []
        for _ in range(100):
            ticket += 1
            chunk = call('result', 'reserve_chunk', result, ticket, 131_300)
            assert chunk > 0
            fixture.inputs[ticket] = b''
            assert call('result', 'reserve_chunk', result, ticket + 100, 131_300) == -3
            assert call('result', 'close', result) == -9
            # Closing an export seals new production, so its already reserved
            # read is retired below; use a separate export for the positive stream.
            assert call('result', 'produce_chunk', chunk) == -5
            assert call('result', 'close_chunk', chunk) == 0
            assert call('result', 'close', result) == 0
            break
        result = call('result', 'reserve', tasks[1], 0)
        assert result > 0 and call('result', 'start', result) == 0
        for _ in range(1000):
            assert call('result', 'feed', result, 1) == 0
            if call('result', 'inputs_ready', result) == 0:
                break
        else:
            raise AssertionError('Second Result bridge did not finish')
        for _ in range(1000):
            assert call('result', 'advance', result, 1) == 0
            if call('result', 'progress', result, 0) == 1:
                break
        else:
            raise AssertionError('Second Result preparation did not finish')
        assert call('result', 'finish_preparation', result) == 0
        if final_publication:
            _, retention_wire = publication_policy()
            pending_input = copy({'results': [result],
                                  'max_work': 1000000, 'max_workspace_slots': 100000})
            ticket += 1
            fixture.inputs[ticket] = b''
            pending_publication = call('publication', 'reserve', source_pin, pending_input,
                                       ticket, 2097200)
            assert pending_publication > 0
            pending_status = call('publication', 'prepare', pending_publication, configuration)
            assert pending_status == -2, ('Unfinished Result publication prepare', pending_status)
            assert_status('publication', 'length', -33, pending_publication)
            assert_status('publication', 'close', 0, pending_publication)
            publication_cases.append('unfinished_original_result_export_cannot_attest_publication')
        for _ in range(100):
            ticket += 1
            chunk = call('result', 'reserve_chunk', result, ticket, 131_300)
            assert chunk > 0
            fixture.inputs[ticket] = b''
            assert call('result', 'produce_chunk', chunk) == 0
            assert call('result', 'produce_chunk', chunk) == 0, 'Acknowledgement loss must not consume another chunk'
            size = call('result', 'chunk_length', chunk)
            assert 0 <= size <= 65_536
            chunks.append(bytes(fixture.call('byte', chunk, index) for index in range(size)))
            final = call('result', 'chunk_final', chunk)
            assert final in (0, 1)
            assert call('result', 'close_chunk', chunk) == 0
            if final:
                break
        else:
            raise AssertionError('No acknowledged export terminator')
        assert b''.join(chunks) == b'[{"next":5}]'
        assert fixture.queries == 3, 'Result reads must not repeat Source or Compute'
        if final_publication:
            expected, retention_wire = publication_policy()

            def publication_loan(**overrides):
                global ticket
                request = copy({'results': [result],
                                'max_work': 1000000, 'max_workspace_slots': 100000,
                                **overrides})
                ticket += 1
                fixture.inputs[ticket] = b''
                value = call('publication', 'reserve', source_pin, request, ticket, 2097200)
                assert value > 0
                return value

            for supplied, code in ((None, -31), ([], -31), ([result, result], -2), ([tasks[0]], -2)):
                value = publication_loan(results=supplied)
                assert_status('publication', 'prepare', code, value, configuration)
                assert_status('publication', 'length', -33, value)
                assert_status('publication', 'close', 0, value)
            publication_cases.append('null_empty_duplicate_foreign_result_inventory_refused')
            missing = copy({'max_work': 100,
                            'max_workspace_slots': 100000})
            ticket += 1
            fixture.inputs[ticket] = b''
            value = call('publication', 'reserve', source_pin, missing, ticket, 2097200)
            assert value > 0
            assert_status('publication', 'prepare', -31, value, configuration)
            assert_status('publication', 'length', -33, value)
            assert_status('publication', 'close', 0, value)
            publication_cases.append('absent_inventory_is_not_null_or_full_inventory')
            exhausted = publication_loan(max_work=1)
            assert_status('publication', 'prepare', 0, exhausted, configuration)
            assert_status('publication', 'finish', -7, exhausted, configuration)
            assert_status('publication', 'advance', 0, exhausted, configuration, 1)
            assert_status('publication', 'advance', -32, exhausted, configuration, 1)
            assert_status('publication', 'progress', 1, exhausted, 2)
            assert_status('publication', 'length', -33, exhausted)
            assert_status('publication', 'close', 0, exhausted)
            assert call('compute', 'configured', compute) == 0
            # Retention was checked before activation. A later child may
            # borrow the original projection, but cannot supply any policy.
            foreign_retention = json.loads(expected['retention_preimage'])
            foreign_retention['clock_contract_cid'] = 'sha256:' + '8' * 64
            foreign_retention['effective_retention_policy_cid'] = 'sha256:' + hashlib.sha256(encode(foreign_retention)).hexdigest()
            foreign = publication_loan(retention=encode(foreign_retention).decode())
            assert_status('publication', 'prepare', -31, foreign, configuration)
            assert_status('publication', 'length', -33, foreign)
            assert_status('publication', 'close', 0, foreign)
            publication_cases.append('unfinished_budget_refusal_retains_work_and_original_compute')
            denied_account = json.loads(account)
            denied_account['entries'][0]['outcome'] = 'deny'
            denied_configuration = call('run', 'install_configuration', copy({
                **CONFIGURATION, 'account': encode(denied_account).decode()}))
            assert denied_configuration > 0
            revoked = publication_loan()
            assert_status('publication', 'prepare', 0, revoked, configuration)
            assert_status('publication', 'prepare', -32, revoked, denied_configuration)
            assert_status('publication', 'advance', -32, revoked, denied_configuration, 7)
            assert_status('publication', 'length', -33, revoked)
            assert_status('publication', 'close', 0, revoked)
            publication_cases.append('current_authority_checked_before_each_owner_yield')
            expected_work = expected_body = None
            for quantum in (7, 100):
                value = publication_loan()
                if result_binding and quantum == 7:
                    observations = json.loads((root / 'scripts/fixtures/python-local-result-storage-binding.json').read_text())
                    before_completion = copy({key: observations[key] for key in (
                        'material_generation_cid', 'store_authority_cid', 'byte_count', 'physical_sha256')})
                    ticket += 1
                    fixture.inputs[ticket] = b''
                    assert_status('result_binding', 'reserve', -2, value, 0, before_completion, ticket, 131300)
                    fixture.inputs.pop(ticket)
                    assert fixture.call('close', before_completion) == 0
                if commit_candidate and quantum == 7:
                    assert_status('publication', 'retire_output', -33, value)
                    publication_retirement_cases.append('unfinished_output_cannot_retire_semantic_custody')
                assert_status('publication', 'prepare', 0, value, configuration)
                if commit_candidate:
                    assert_status('publication_commit_export', 'reserve', -2, value, ticket + 1, 2097200)
                spent = 0
                for _ in range(100000):
                    advanced = call('publication', 'advance', value, configuration, quantum)
                    assert advanced == 0, ('Original bounded publication Owner refusal', advanced, spent)
                    used = call('publication', 'progress', value, 1)
                    assert 0 <= used <= quantum
                    spent += used
                    if call('publication', 'progress', value, 0) == 1:
                        break
                else:
                    raise AssertionError('Final publication did not complete within the fixture bound')
                assert call('publication', 'progress', value, 2) == spent
                if expected_work is None:
                    expected_work = spent
                assert spent == expected_work
                assert_status('publication', 'finish', -32, value, denied_configuration)
                assert_status('publication', 'length', -33, value)
                assert_status('publication', 'finish', 0, value, configuration)
                assert_status('publication', 'finish', -32, value, denied_configuration)
                assert_status('publication', 'finish', 0, value, configuration)
                size = call('publication', 'length', value)
                assert 0 < size <= 1048576
                body = json.loads(bytes(fixture.call('byte', value, index) for index in range(size)))
                assert set(body) == {'manifest', 'receipt', 'captured_run'}
                manifest, receipt, captured = (json.loads(body[key]) for key in ('manifest', 'receipt', 'captured_run'))
                assert manifest['version'] == 'actql-result-manifest/0.1'
                assert set(manifest['results']) == {expected['result_name']}
                assert receipt['version'] == 'actql-run-receipt/0.1'
                frozen = json.loads((root / 'spec/contracts/actql-effect-free-local-completion-free-fixture.json').read_text())
                assert receipt['normalization_journal_cid'] == frozen['journal_cid']
                assert receipt['result_manifest_cid'] == manifest['result_manifest_cid']
                assert captured['version'] == 'actql-captured-run/0.1'
                assert captured['receipt'] == receipt
                context = captured['effect_context']
                assert context['result_values'] == {expected['result_name']: expected['result_rows']}
                assert context['result_fields'] == {expected['result_name']: expected['result_fields']}
                assert context['model_invocation_evidence'] == []
                assert context['pending_source_state_advances'] == []
                assert context['authoring_context']['program_definition_cid'] == receipt['program_definition_cid']
                assert context['authoring_context']['annotations'] == [{
                    'target': {'kind': 'program', 'source_path': '$', 'name': program['id']},
                    'meta': {'note': 'original', 'nested': {'meta': 'presentation'}}}]
                assert captured['encryption_required'] is True
                assert captured['sensitivity'] == 'private'
                if expected_body is None:
                    expected_body = body
                assert body == expected_body, 'Quantum cannot change the original final evidence'
                assert fixture.queries == expected['source_queries']
                if commit_candidate and quantum == 7:
                    retirement = json.loads((root / 'scripts/fixtures/python-local-publication-output-retirement.json').read_text())
                    original_input = projection_inputs[('publication', value)]
                    allocated = fixture.call('allocated')
                    fixture.cleanup_ready = False
                    assert_status('publication', 'retire_output', retirement['pending_status'], value)
                    assert fixture.call('allocated') == allocated
                    fixture.cleanup_ready = True
                    assert_status('publication', 'retire_output', 0, value)
                    assert fixture.call('allocated') == allocated - retirement['allocation_bytes']
                    assert_status('publication', 'retire_output', 0, value)
                    publication_retirement_cases.append('same_output_cleanup_retry_releases_only_exact_allocation')
                    assert_status('publication', 'length', retirement['retired_length_status'], value)
                    assert fixture.call('byte', value, 0) == retirement['retired_byte_status']
                    assert fixture.call('close', original_input) == retirement['input_close_while_borrowed_status']
                    assert_status('publication', 'finish', -32, value, denied_configuration)
                    assert_status('publication', 'finish', 0, value, configuration)
                    assert body == expected_body
                    assert fixture.queries == expected['source_queries']
                    publication_retirement_cases.extend([
                        'retired_output_refuses_reads_and_keeps_original_input_borrow',
                        'original_roots_and_current_authority_survive_output_retirement'])
                payload_child = payload_input = None
                if payload_request and quantum == 7:
                    payload_expected = json.loads((root / 'scripts/fixtures/python-local-payload-request.json').read_text())
                    payload_facts = payload_expected['input']
                    assert len(payload_expected['exact_payload'].encode()) == int(payload_expected['max_bytes'])

                    def payload_loan(facts):
                        global ticket
                        input_handle = copy(facts)
                        ticket += 1
                        fixture.inputs[ticket] = b''
                        child = call('payload_request', 'reserve', value, 0, input_handle, ticket, 131300)
                        assert child > 0, ('Original payload request reserve', child)
                        return child, input_handle

                    for bad in (
                            {key: val for key, val in payload_facts.items() if key != 'material_generation_cid'},
                            {**payload_facts, 'material_generation_cid': None},
                            {**payload_facts, 'max_payload_bytes': True},
                            {**payload_facts, 'max_payload_bytes': 0},
                            {**payload_facts, 'row_count': 1}):
                        child, input_handle = payload_loan(bad)
                        assert_status('payload_request', 'produce', -31, child, configuration)
                        assert_status('payload_request', 'length', -33, child)
                        assert_status('payload_request', 'close', 0, child)
                        assert fixture.call('close', input_handle) == 0
                    child, input_handle = payload_loan({**payload_facts, 'max_payload_bytes': 11})
                    assert_status('payload_request', 'produce', -32, child, configuration)
                    assert_status('payload_request', 'close', 0, child)
                    assert fixture.call('close', input_handle) == 0
                    payload_request_cases.append('closed_request_preserves_absent_null_and_rejects_supplied_result_identity')
                    child, input_handle = payload_loan(payload_facts)
                    if payload_record:
                        assert_status('payload_record', 'reserve', -2, child, 65400, 131300)
                        payload_record_cases.append('unfinished_request_cannot_export_initial_record')
                    if payload_replay:
                        assert_status('payload_request', 'start_replay', -33, child, configuration)
                        assert_status('payload_chunk', 'reserve', -2, child, 65500, 131300)
                        payload_replay_cases.append('unfinished_request_cannot_open_replay')
                    assert_status('payload_request', 'produce', -32, child, denied_configuration)
                    assert_status('payload_request', 'produce', 0, child, configuration)
                    size = call('payload_request', 'length', child)
                    assert 0 < size <= 65536
                    payload_wire = bytes(fixture.call('byte', child, i) for i in range(size))
                    payload_body = json.loads(payload_wire)
                    assert sorted(payload_body) == payload_expected['output_fields']
                    assert payload_body['version'] == payload_expected['version']
                    for key in ('store_authority_cid', 'material_generation_cid'):
                        assert payload_body[key] == payload_facts[key]
                    for key in ('max_bytes', 'row_count'):
                        assert payload_body[key] == payload_expected[key]
                    assert payload_body['publication_attempt_cid'] == original_attempt['publication_attempt_cid']
                    assert payload_body['result_definition_cid'] == original_request['inventory'][0]['result_definition_cid']
                    original_physical = json.loads((root / 'scripts/fixtures/python-local-result-storage-binding.json').read_text())
                    assert payload_body['result_schema_cid'] == original_physical['result_schema_cid']
                    assert payload_body['durable_codec_cid'] == original_physical['codec_contract_cid']
                    payload_request_cases.append('original_result_and_attempt_project_exact_bounded_payload_intent')
                    assert_status('payload_request', 'produce', -32, child, denied_configuration)
                    assert_status('payload_request', 'produce', 0, child, configuration)
                    assert bytes(fixture.call('byte', child, i) for i in range(size)) == payload_wire
                    payload_request_cases.append('current_authority_revalidated_after_cached_projection')
                    if payload_record:
                        import sqlite3
                        from tempfile import TemporaryDirectory
                        from unittest.mock import patch
                        from actql_sdk._local_storage import ByteWrite, LocalByteStore, StoredBytes

                        record_expected = json.loads((root / 'scripts/fixtures/python-local-payload-record.json').read_text())
                        record_request, record_input = payload_loan(payload_facts)
                        assert_status('payload_request', 'produce', 0, record_request, configuration)
                        ticket += 1
                        record_ticket = ticket
                        fixture.inputs[ticket] = b''
                        record_child = call('payload_record', 'reserve', record_request, ticket, record_expected['physical_copy_bytes'])
                        assert record_child > 0, ('Original payload record reserve', record_child)
                        assert_status('payload_record', 'produce', -32, record_child, denied_configuration)
                        assert_status('payload_record', 'produce', 0, record_child, configuration)
                        record_length = call('payload_record', 'length', record_child)
                        assert 0 < record_length <= record_expected['max_record_bytes']
                        record_wire = bytes(fixture.call('byte', record_child, i) for i in range(record_length))
                        record_body = json.loads(record_wire)
                        assert set(record_body) == set(record_expected['initial_fields']) | {'request_cid', 'request_json', 'version'}
                        assert record_body['version'] == record_expected['record_version']
                        for field, expected_value in record_expected['initial_fields'].items():
                            assert record_body[field] == expected_value, (field, record_body[field])
                        assert record_body['request_json'].encode() == payload_wire
                        assert_status('payload_record', 'validate', -32, record_child, denied_configuration)
                        assert_status('payload_record', 'validate', 0, record_child, configuration)
                        payload_record_cases.append('original_intent_and_current_authority_preserved')

                        observation = {'store_authority_cid': payload_facts['store_authority_cid'],
                                       'material_generation_cid': payload_facts['material_generation_cid'],
                                       'physical_revision': 0, 'record_json': record_wire.decode()}
                        ack = copy(observation)
                        assert_status('payload_record', 'confirm', -33, record_child, ack, configuration)
                        fixture.cleanup_ready = True
                        assert fixture.call('close', ack) == 0
                        assert_status('payload_record', 'begin', 0, record_child, configuration)
                        assert_status('payload_record', 'begin', -33, record_child, configuration)
                        for bad in (
                                {**observation, 'store_authority_cid': 'sha256:' + 'a' * 64},
                                {**observation, 'material_generation_cid': 'sha256:' + 'a' * 64},
                                {**observation, 'physical_revision': 1},
                                {**observation, 'record_json': record_wire.decode().replace('"state":"intent"', '"state":"reserved"')}):
                            bad_ack = copy(bad)
                            assert_status('payload_record', 'confirm', -32, record_child, bad_ack, configuration)
                            assert fixture.call('close', bad_ack) == 0
                        payload_record_cases.append('foreign_store_key_revision_and_bytes_do_not_confirm')

                        class LostRecordCommit(sqlite3.Connection):
                            writes = 0
                            lose = False

                            def execute(self, sql, *args, **kwargs):
                                if sql.startswith(('INSERT', 'UPDATE')):
                                    self.writes += 1
                                result = super().execute(sql, *args, **kwargs)
                                if sql == 'COMMIT' and self.lose:
                                    self.lose = False
                                    raise OSError('Original initial record acknowledgement lost')
                                return result

                        physical_connect = sqlite3.connect
                        with TemporaryDirectory(prefix='actql-abi28-initial-record-') as directory:
                            with patch('actql_sdk._local_storage.sqlite3.connect',
                                       side_effect=lambda *a, **k: physical_connect(*a, **k, factory=LostRecordCommit)):
                                with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4,
                                                    max_record_bytes=65536, max_payload_bytes=262144) as store:
                                    write = ByteWrite(payload_facts['material_generation_cid'], None, record_wire)
                                    assert store.read_exchange(write) is None
                                    store._connection.lose = True
                                    try:
                                        store.compare_exchange(write.key, None, write.payload)
                                    except OSError as error:
                                        assert str(error) == 'Original initial record acknowledgement lost'
                                    else:
                                        raise AssertionError('Missing original lost-ack counterexample')
                                    assert store._connection.writes == 1
                                    assert_status('payload_record', 'close', -9, record_child)
                                    assert_status('payload_request', 'close', -9, record_request)
                                    assert fixture.call('close', record_input) == -9
                                    actual = store.read_exchange(write)
                                    assert actual == StoredBytes(record_expected['physical_revision'], record_wire)
                                    assert store._connection.writes == 1
                                    payload_record_cases.append('lost_cas_acknowledgement_never_repeats_write')
                                    actual_ack = copy({**observation, 'physical_revision': actual.generation,
                                                      'record_json': actual.payload.decode()})
                                    assert_status('payload_record', 'confirm', -32, record_child, actual_ack, denied_configuration)
                                    assert_status('payload_record', 'confirm', 0, record_child, actual_ack, configuration)
                                    assert_status('payload_record', 'confirm', 0, record_child, actual_ack, configuration)
                                    assert fixture.call('close', actual_ack) == 0
                                    assert store.read(write.key) == StoredBytes(0, record_wire)
                                    payload_record_cases.append('same_initial_record_confirmed_without_capacity_or_publication')
                        allocated = fixture.call('allocated')
                        fixture.cleanup_ready = False
                        assert_status('payload_record', 'close', -9, record_child)
                        assert fixture.call('allocated') == allocated
                        fixture.cleanup_ready = True
                        assert_status('payload_record', 'close', 0, record_child)
                        assert fixture.call('allocated') == allocated - (2 * 65536 + record_expected['physical_copy_bytes'])
                        assert_status('payload_record', 'close', -2, record_child)
                        assert_status('payload_request', 'close', 0, record_request)
                        assert fixture.call('close', record_input) == 0
                        assert fixture.queries == expected['source_queries']
                        payload_record_cases.append('pending_close_and_cleanup_retain_original_request_and_input')
                        assert payload_record_cases == record_expected['cases']
                    if payload_reservation:
                        from python_local_payload_reservation import check_payload_reservation

                        def new_output_ticket():
                            global ticket
                            ticket += 1
                            fixture.inputs[ticket] = b''
                            return ticket

                        payload_reservation_cases.extend(check_payload_reservation(
                            fixture, payload_loan, payload_facts, configuration, denied_configuration,
                            copy, call, assert_status, new_output_ticket))
                        assert fixture.queries == expected['source_queries']
                    if payload_writing:
                        from python_local_payload_writing import check_payload_writing
                        payload_writing_cases.extend(check_payload_writing(
                            fixture, payload_loan, payload_facts, configuration, denied_configuration,
                            copy, call, assert_status, new_output_ticket))
                        assert fixture.queries == expected['source_queries']
                    if payload_allocation:
                        from python_local_payload_allocation import check_payload_allocation
                        payload_allocation_cases.extend(check_payload_allocation(
                            fixture, payload_loan, payload_facts, configuration, denied_configuration,
                            copy, call, assert_status, new_output_ticket))
                        assert fixture.queries == expected['source_queries']
                    if payload_sealed:
                        from python_local_payload_sealed import check_payload_sealed
                        names_observer = None
                        if payload_names:
                            from python_local_payload_names import PayloadNameCases
                            staging_observer = None
                            if payload_staging:
                                from python_local_payload_staging import PayloadStagingCases
                                staging_observer = PayloadStagingCases()
                            finalization_observer = None
                            if payload_finalization:
                                from python_local_payload_finalization import PayloadFinalizationCases
                                reader_observer = None
                                if payload_reader:
                                    from python_local_payload_reader import PayloadReaderCases
                                    reader_observer = PayloadReaderCases()
                                finalization_observer = PayloadFinalizationCases(reader_observer)
                            names_observer = PayloadNameCases(fixture, configuration, denied_configuration,
                                                              call, assert_status, new_output_ticket, staging_observer,
                                                              finalization_observer)
                        payload_sealed_cases.extend(check_payload_sealed(
                            fixture, payload_loan, payload_facts, configuration, denied_configuration,
                            copy, call, assert_status, new_output_ticket, names_observer,
                            payload_binding_cases if payload_binding else None))
                        if names_observer is not None:
                            payload_names_cases.extend(names_observer.finish())
                            if names_observer.staging is not None:
                                payload_staging_cases.extend(names_observer.staging.finish())
                            if names_observer.finalization is not None:
                                payload_finalization_cases.extend(names_observer.finalization.finish())
                                if names_observer.finalization.reader is not None:
                                    payload_reader_cases.extend(names_observer.finalization.reader.finish())
                        assert fixture.queries == expected['source_queries']
                    if payload_replay:
                        replay_expected = json.loads((root / 'scripts/fixtures/python-local-payload-replay.json').read_text())
                        assert_status('payload_request', 'start_replay', -32, child, denied_configuration)
                        assert_status('payload_request', 'start_replay', 0, child, configuration)
                        assert_status('payload_request', 'start_replay', 0, child, configuration)
                        payload_replay_cases.append('original_request_and_result_open_once_under_current_custody')
                        ticket += 1
                        assert_status('payload_chunk', 'reserve', -4, child, ticket, 8388608)
                        payload_replay_cases.append('capacity_refusal_before_replay_advance')
                        payload_parts = []
                        for _ in range(100):
                            ticket += 1
                            fixture.inputs[ticket] = b''
                            chunk = call('payload_chunk', 'reserve', child, ticket, replay_expected['physical_copy_bytes'])
                            assert chunk > 0
                            assert_status('payload_chunk', 'reserve', -3, child, ticket + 1, replay_expected['physical_copy_bytes'])
                            assert_status('payload_chunk', 'produce', -32, chunk, denied_configuration)
                            assert_status('payload_chunk', 'produce', 0, chunk, configuration)
                            assert_status('payload_chunk', 'produce', 0, chunk, configuration)
                            assert_status('payload_chunk', 'validate', -32, chunk, denied_configuration)
                            assert_status('payload_chunk', 'validate', 0, chunk, configuration)
                            length = call('payload_chunk', 'length', chunk)
                            assert 0 <= length <= replay_expected['max_chunk_bytes']
                            wire = bytes(fixture.call('byte', chunk, index) for index in range(length))
                            assert bytes(fixture.call('byte', chunk, index) for index in range(length)) == wire
                            payload_parts.append(wire)
                            final = call('payload_chunk', 'final', chunk)
                            assert final in (0, 1)
                            if final:
                                assert_status('payload_request', 'close', -9, child)
                                assert fixture.call('close', input_handle) == -9
                            held = fixture.call('allocated')
                            fixture.cleanup_ready = False
                            assert_status('payload_chunk', 'close', -9, chunk)
                            assert fixture.call('allocated') == held
                            fixture.cleanup_ready = True
                            assert_status('payload_chunk', 'close', 0, chunk)
                            assert fixture.call('allocated') == held - (2 * 65536 + replay_expected['physical_copy_bytes'])
                            assert_status('payload_chunk', 'produce', -2, chunk, configuration)
                            assert_status('payload_chunk', 'validate', -2, chunk, configuration)
                            if final:
                                break
                        else:
                            raise AssertionError('No original payload replay terminator')
                        assert b''.join(payload_parts) == replay_expected['exact_payload'].encode('utf-8')
                        assert fixture.queries == expected['source_queries']
                        payload_replay_cases.extend([
                            'bounded_chunk_and_lost_ack_use_same_original_bytes',
                            'current_authority_rechecked_for_production_and_cached_read',
                            'failed_chunk_cleanup_retains_exact_allocation_for_retry',
                            'live_final_chunk_keeps_parent_request_and_original_borrow',
                            'exact_replay_eof_and_stale_chunk_refusal_without_source_compute_repeat'])
                        assert payload_replay_cases == replay_expected['cases']
                    allocated = fixture.call('allocated')
                    fixture.cleanup_ready = False
                    assert_status('payload_request', 'close', -9, child)
                    assert fixture.call('allocated') == allocated
                    assert fixture.call('close', input_handle) == -9
                    payload_request_cases.append('failed_cleanup_keeps_same_child_input_and_exact_allocation')
                    fixture.cleanup_ready = True
                    fixture.stop_ready = False
                    assert_status('payload_request', 'close', -9, child)
                    assert fixture.call('close', input_handle) == -9
                    fixture.stop_ready = True
                    assert_status('payload_request', 'close', 0, child)
                    assert fixture.call('close', input_handle) == 0
                    assert_status('payload_request', 'length', -2, child)
                    assert_status('payload_request', 'close', -2, child)
                    payload_request_cases.append('input_stop_retry_and_stale_child_refusal')
                    payload_child, payload_input = payload_loan(payload_facts)
                    assert_status('payload_request', 'produce', 0, payload_child, configuration)
                    assert fixture.queries == expected['source_queries']
                if result_binding and quantum == 7:
                    physical = json.loads((root / 'scripts/fixtures/python-local-result-storage-binding.json').read_text())
                    # These hashes are independently fixed from authored UTF-8
                    # bytes, not learned from this module's binding response.
                    assert physical['payload'].encode() == b'[{"next":5}]'
                    assert hashlib.sha256(physical['payload'].encode()).hexdigest() == physical['physical_sha256']
                    facts = {key: physical[key] for key in (
                        'material_generation_cid', 'store_authority_cid', 'byte_count', 'physical_sha256')}

                    def binding_loan(observations):
                        global ticket
                        input_handle = copy(observations)
                        ticket += 1
                        fixture.inputs[ticket] = b''
                        loan = call('result_binding', 'reserve', value, 0, input_handle, ticket, 131300)
                        assert loan > 0, ('Original Result binding reservation', loan)
                        return loan, input_handle

                    for bad, expected_status in (
                            ({**facts, 'byte_count': 11}, -32),
                            ({**facts, 'physical_sha256': '0' * 64}, -32),
                            ({**facts, 'byte_count': None}, -31),
                            ({key: val for key, val in facts.items() if key != 'byte_count'}, -31),
                            ({**facts, 'row_count': 1}, -31)):
                        loan, input_handle = binding_loan(bad)
                        assert_status('result_binding', 'produce', expected_status, loan, configuration)
                        assert_status('result_binding', 'length', -33, loan)
                        assert_status('result_binding', 'close', 0, loan)
                        assert fixture.call('close', input_handle) == 0
                    binding_cases.append('closed_physical_facts_and_exact_bytes_refused')
                    loan, input_handle = binding_loan(facts)
                    assert_status('result_binding', 'produce', -32, loan, denied_configuration)
                    assert_status('result_binding', 'produce', 0, loan, configuration)
                    assert_status('result_binding', 'produce', -32, loan, denied_configuration)
                    assert_status('result_binding', 'produce', 0, loan, configuration)
                    size = call('result_binding', 'length', loan)
                    assert 0 < size <= 65536
                    binding_wire = bytes(fixture.call('byte', loan, i) for i in range(size)).decode('utf-8')
                    binding = json.loads(binding_wire)
                    for key in ('byte_count', 'physical_sha256', 'row_count', 'result_fields',
                                'result_schema_cid', 'codec_contract_cid', 'material_generation_cid', 'store_authority_cid'):
                        assert binding[key] == physical[key], ('Independent Result binding field', key, binding[key])
                    assert binding['effective_retention_policy_cid'] == expected['retention_policy_cid']
                    assert binding['version'] == 'actql-durable-result-binding/0.1'
                    binding_cases.append('original_result_binding_and_current_authority')
                    reserved = fixture.call('reserved')
                    fixture.cleanup_ready = False
                    assert_status('result_binding', 'close', -9, loan)
                    assert fixture.call('reserved') == reserved
                    assert fixture.call('close', input_handle) == -9
                    fixture.cleanup_ready = True
                    fixture.stop_ready = False
                    assert_status('result_binding', 'close', -9, loan)
                    assert fixture.call('close', input_handle) == -9
                    fixture.stop_ready = True
                    assert_status('result_binding', 'close', 0, loan)
                    assert fixture.call('close', input_handle) == 0
                    binding_cases.append('same_input_borrow_stop_and_cleanup_retry')
                    if commit_candidate:
                        commit_expected = json.loads((root / 'scripts/fixtures/python-local-commit-candidate.json').read_text())

                        def complete_candidate_publication():
                            child = publication_loan()
                            assert_status('publication', 'prepare', 0, child, configuration)
                            for _ in range(100000):
                                assert_status('publication', 'advance', 0, child, configuration, 100)
                                if call('publication', 'progress', child, 0) == 1:
                                    break
                            else:
                                raise AssertionError('Candidate publication exceeded the original fixture bound')
                            assert_status('publication', 'finish', 0, child, configuration)
                            return child

                        # Each malformed attempt retains its own original input;
                        # later inputs cannot restart that same invocation.
                        import rfc8785
                        wrong_run = {key: val for key, val in binding.items()
                                     if key != 'durable_result_binding_cid'}
                        wrong_run['run_definition_cid'] = 'sha256:' + '0' * 64
                        wrong_run['durable_result_binding_cid'] = 'sha256:' + hashlib.sha256(
                            rfc8785.dumps(wrong_run)).hexdigest()
                        for bad in ({'bindings': None}, {'bindings': []},
                                    {'bindings': [binding_wire, binding_wire]},
                                    {'bindings': [binding_wire], 'request': preflight_body['request']},
                                    {'bindings': [encode(wrong_run).decode()]}):
                            child = complete_candidate_publication()
                            bad_input = copy({'committed_at': commit_expected['committed_at'], **bad})
                            assert_status('publication', 'prepare_commit', -32, child, bad_input, configuration)
                            assert_status('publication', 'finish_commit', -33, child, configuration)
                            assert_status('publication_commit_export', 'reserve', -2, child, ticket + 1, 2097200)
                            assert fixture.call('close', bad_input) == -9
                            assert_status('publication', 'close', 0, child)
                            assert fixture.call('close', bad_input) == 0
                        # A shape-valid, independently rehashed binding with a
                        # foreign logical Result must reach the full validator
                        # and still cannot yield a candidate export.
                        wrong_logical = {key: val for key, val in binding.items()
                                         if key != 'durable_result_binding_cid'}
                        wrong_logical['logical_result_cid'] = 'sha256:' + '0' * 64
                        wrong_logical['durable_result_binding_cid'] = 'sha256:' + hashlib.sha256(
                            rfc8785.dumps(wrong_logical)).hexdigest()
                        child = complete_candidate_publication()
                        bad_input = copy({'bindings': [encode(wrong_logical).decode()],
                                          'committed_at': commit_expected['committed_at']})
                        assert_status('publication', 'prepare_commit', 0, child, bad_input, configuration)
                        for _ in range(100000):
                            status = call('publication', 'advance_commit', child, configuration, 100)
                            if status == -32:
                                break
                            assert status == 0
                            if call('publication', 'commit_progress', child, 0) == 1:
                                assert_status('publication', 'finish_commit', -32, child, configuration)
                                break
                        else:
                            raise AssertionError('Foreign logical Result was not refused within the fixture bound')
                        assert call('publication', 'commit_progress', child, 2) < 1000000
                        assert_status('publication_commit_export', 'reserve', -2, child, ticket + 1, 2097200)
                        assert_status('publication', 'close', 0, child)
                        assert fixture.call('close', bad_input) == 0
                        commit_cases.append('closed_candidate_input_and_original_binding_inventory')

                        commit_input = copy({'bindings': [binding_wire],
                                             'committed_at': commit_expected['committed_at']})
                        assert_status('publication', 'prepare_commit', 0, value, commit_input, configuration)
                        assert_status('publication', 'finish_commit', -7, value, configuration)
                        if commit_materials:
                            material_expected = json.loads((root / 'scripts/fixtures/python-local-commit-material.json').read_text())
                            assert_status('publication_commit_export', 'count', -32, value, configuration)
                            commit_material_cases.append('unfinished_original_view_refuses_count')
                        assert_status('publication_commit_export', 'reserve', -2, value, ticket + 1, 2097200)
                        commit_start_work = call('publication', 'commit_progress', value, 2)
                        commit_work = 0
                        assert_status('publication', 'advance_commit', -32, value, denied_configuration, 7)
                        for _ in range(100000):
                            assert_status('publication', 'advance_commit', 0, value, configuration, 7)
                            used = call('publication', 'commit_progress', value, 1)
                            assert 0 <= used <= 7
                            commit_work += used
                            if call('publication', 'commit_progress', value, 0) == 1:
                                break
                        else:
                            raise AssertionError('Candidate validator exceeded the original fixture bound')
                        assert commit_work > 0
                        assert call('publication', 'commit_progress', value, 2) == commit_start_work + commit_work
                        assert_status('publication', 'finish_commit', -32, value, denied_configuration)
                        assert_status('publication', 'finish_commit', 0, value, configuration)
                        assert_status('publication', 'finish_commit', 0, value, configuration)
                        replacement = copy({'bindings': [binding_wire],
                                            'committed_at': '2026-10-10T00:00:05.000Z'})
                        assert_status('publication', 'prepare_commit', -2, value, replacement, configuration)
                        assert call('publication', 'commit_progress', value, 2) == commit_start_work + commit_work
                        assert fixture.call('close', replacement) == 0
                        assert fixture.call('close', commit_input) == -9
                        commit_cases.append('full_chain_validation_and_shared_work_budget')

                        if commit_materials:
                            assert_status('publication_commit_export', 'count', material_expected['count'], value, configuration)
                            assert_status('publication_commit_export', 'count', -32, value, denied_configuration)
                            assert_status('publication_commit_export', 'count', -2, value + 100000, configuration)
                            commit_material_cases.append('original_count_and_current_authority_refusal')

                            def material_child():
                                global ticket
                                ticket += 1
                                fixture.inputs[ticket] = b''
                                loan = call('publication_commit_export', 'reserve', value, ticket, 2097200)
                                assert loan > 0
                                return loan

                            def material_bytes(loan):
                                size = call('publication_commit_export', 'length', loan)
                                assert 0 < size <= 1048576
                                return bytes(fixture.call('byte', loan, i) for i in range(size))

                            # Names, identity fields, count and order are independently
                            # fixed. Comparing retained original wires proves byte
                            # custody, not a generated semantic expectation.
                            original_wires = {2: body['manifest'], 3: body['receipt'],
                                              4: body['captured_run'], 5: preflight_body['request'],
                                              6: preflight_body['attempt'], 13: binding_wire}
                            for ordinal, (name, identity_field) in enumerate(material_expected['materials']):
                                original_body = None
                                for field in range(4):
                                    loan = material_child()
                                    assert_status('publication_commit_export', 'produce_material', -32,
                                                  loan, denied_configuration, ordinal, field)
                                    assert_status('publication_commit_export', 'produce_material', 0,
                                                  loan, configuration, ordinal, field)
                                    raw = material_bytes(loan)
                                    if field == 0:
                                        original_body = json.loads(raw)
                                        assert original_body['version'].startswith('actql-')
                                        if ordinal in original_wires:
                                            assert raw == original_wires[ordinal].encode('utf-8')
                                    elif field == 1:
                                        assert raw == name.encode('utf-8')
                                    elif field == 2:
                                        assert raw == identity_field.encode('utf-8')
                                    else:
                                        assert original_body is not None
                                        assert raw == original_body[identity_field].encode('utf-8')
                                    assert_status('publication_commit_export', 'close', 0, loan)
                                    assert_status('publication_commit_export', 'length', -2, loan)
                            commit_material_cases.append('all_original_ordinals_and_four_raw_fields')
                            commit_material_cases.append('original_root_and_binding_bytes_match_retained_custody')
                            loan = material_child()
                            assert_status('publication_commit_export', 'produce_material', 0, loan, configuration, 5, 0)
                            assert_status('publication_commit_export', 'produce_material', 0, loan, configuration, 5, 0)
                            assert_status('publication_commit_export', 'produce_material', -32, loan, denied_configuration, 5, 0)
                            assert_status('publication_commit_export', 'produce_material', -33, loan, configuration, 6, 0)
                            assert_status('publication_commit_export', 'produce_material', -33, loan, configuration, 5, 1)
                            assert_status('publication_commit_export', 'produce', -33, loan, configuration)
                            assert material_bytes(loan) == preflight_body['request'].encode('utf-8')
                            commit_material_cases.append('immutable_child_projection_and_cached_current_access')
                            assert_status('publication_commit_export', 'produce_material', -3, loan, configuration, -1, 0)
                            assert_status('publication_commit_export', 'produce_material', -3, loan, configuration, 5, 4)
                            assert_status('publication_commit_export', 'close', 0, loan)
                            loan = material_child()
                            assert_status('publication_commit_export', 'produce_material', -32, loan, configuration, 14, 0)
                            assert_status('publication_commit_export', 'length', -33, loan)
                            # Invalid selection made no production; a valid original
                            # ordinal is still usable without a second execution.
                            assert_status('publication_commit_export', 'produce_material', 0, loan, configuration, 5, 0)
                            commit_material_cases.append('invalid_controls_and_out_of_range_refusal')
                            allocated = fixture.call('allocated')
                            fixture.cleanup_ready = False
                            assert_status('publication_commit_export', 'close', -9, loan)
                            assert fixture.call('allocated') == allocated
                            assert_status('publication_commit_export', 'produce_material', -5, loan, configuration, 5, 0)
                            assert_status('publication_commit_export', 'length', -33, loan)
                            assert fixture.call('close', commit_input) == -9
                            fixture.cleanup_ready = True
                            assert_status('publication_commit_export', 'close', 0, loan)
                            assert_status('publication_commit_export', 'length', -2, loan)
                            assert_status('publication_commit_export', 'count', material_expected['count'], value, configuration)
                            assert fixture.queries == expected['source_queries']
                            assert call('publication', 'commit_progress', value, 2) == commit_start_work + commit_work
                            commit_material_cases.append('same_material_cleanup_retry_and_retired_read_refusal')
                        if commit_index_key:
                            key_expected = json.loads((root / 'scripts/fixtures/python-local-commit-index-key.json').read_text())
                            key_loan = material_child()
                            assert_status('publication_commit_export', 'produce_index_key', -32, key_loan, denied_configuration)
                            assert_status('publication_commit_export', 'produce_index_key', 0, key_loan, configuration)
                            original_index_key = material_bytes(key_loan)
                            assert len(original_index_key) == 64
                            assert all(c in b'0123456789abcdef' for c in original_index_key)
                            commit_index_key_cases.append('original_key_and_current_authority_refusal')
                            assert_status('publication_commit_export', 'produce_index_key', 0, key_loan, configuration)
                            assert_status('publication_commit_export', 'produce_index_key', -32, key_loan, denied_configuration)
                            assert_status('publication_commit_export', 'produce_material', -33, key_loan, configuration, 7, 0)
                            assert_status('publication_commit_export', 'produce', -33, key_loan, configuration)
                            assert material_bytes(key_loan) == original_index_key
                            commit_index_key_cases.append('immutable_projection_and_cached_current_access')
                            allocated = fixture.call('allocated')
                            fixture.cleanup_ready = False
                            assert_status('publication_commit_export', 'close', -9, key_loan)
                            assert fixture.call('allocated') == allocated
                            assert_status('publication_commit_export', 'produce_index_key', -5, key_loan, configuration)
                            assert_status('publication_commit_export', 'length', -33, key_loan)
                            assert fixture.call('close', commit_input) == -9
                            fixture.cleanup_ready = True
                            assert_status('publication_commit_export', 'close', 0, key_loan)
                            assert_status('publication_commit_export', 'length', -2, key_loan)
                            commit_index_key_cases.append('same_key_cleanup_retry_and_retired_read_refusal')
                        ticket += 1
                        fixture.inputs[ticket] = b''
                        commit_export = call('publication_commit_export', 'reserve', value, ticket, 2097200)
                        assert commit_export > 0
                        assert_status('publication_commit_export', 'length', -33, commit_export)
                        assert_status('publication_commit_export', 'produce', -32, commit_export, denied_configuration)
                        assert_status('publication_commit_export', 'produce', 0, commit_export, configuration)
                        if commit_materials:
                            assert_status('publication_commit_export', 'produce_material', -33, commit_export, configuration, 5, 0)
                        if commit_index_key:
                            assert_status('publication_commit_export', 'produce_index_key', -33, commit_export, configuration)
                        assert_status('publication_commit_export', 'produce', -32, commit_export, denied_configuration)
                        assert_status('publication_commit_export', 'produce', 0, commit_export, configuration)
                        size = call('publication_commit_export', 'length', commit_export)
                        assert 0 < size <= 1048576
                        proposal = json.loads(bytes(fixture.call('byte', commit_export, i) for i in range(size)))
                        assert sorted(proposal) == commit_expected['output_fields']
                        assert proposal['request'] == preflight_body['request']
                        assert proposal['attempt'] == preflight_body['attempt']
                        index = json.loads(proposal['index_entry'])
                        assert sorted(index) == sorted(commit_expected['index_fields'])
                        assert index['version'] == commit_expected['index_version']
                        assert index['committed_at'] == commit_expected['committed_at']
                        assert index['namespace_id'] == intent_facts['namespace_id']
                        assert index['authority_scope_cid'] == CONFIGURATION['authority_scope_cid']
                        # These references name the original independently tested
                        # parent contracts, not values copied from this candidate.
                        for field, original in (
                            ('publication_request_cid', preflight_body['request']),
                            ('publication_attempt_cid', preflight_body['attempt']),
                            ('result_manifest_cid', body['manifest']),
                            ('run_receipt_cid', body['receipt']),
                            ('captured_run_cid', body['captured_run']),
                        ):
                            original_field = 'receipt_identity_cid' if field == 'run_receipt_cid' else field
                            assert index[field] == json.loads(original)[original_field]
                        assert index['run_definition_cid'] == original_request['run_definition_cid']
                        if commit_index_key:
                            # Independent addressing preimage from the retained original
                            # intent/configuration/request, not from the projected key.
                            # Fixed literal Unicode vectors test the algorithm separately.
                            key_preimage = json.dumps({
                                'authority_scope_cid': CONFIGURATION['authority_scope_cid'],
                                'namespace_id': intent_facts['namespace_id'],
                                'run_definition_cid': original_request['run_definition_cid'],
                                'version': 'actql-public-index-key/0.1',
                            }, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
                            assert original_index_key == hashlib.sha256(key_preimage).hexdigest().encode('ascii')
                            commit_index_key_cases.append('key_matches_original_index_scope')
                            assert fixture.queries == expected['source_queries']
                            assert call('publication', 'commit_progress', value, 2) == commit_start_work + commit_work
                            commit_index_key_cases.append('shared_work_and_source_queries_unchanged')

                        assert index['invocation_cid'] == json.loads(body['manifest'])['invocation_cid']
                        assert index['durable_result_binding_cids'] == [binding['durable_result_binding_cid']]
                        assert len(index['durable_result_binding_cids']) == commit_expected['binding_count']
                        expected_index_body = {
                            'version': commit_expected['index_version'],
                            'committed_at': commit_expected['committed_at'],
                            'namespace_id': intent_facts['namespace_id'],
                            'authority_scope_cid': CONFIGURATION['authority_scope_cid'],
                            'run_definition_cid': original_request['run_definition_cid'],
                            'invocation_cid': manifest['invocation_cid'],
                            'publication_request_cid': original_request['publication_request_cid'],
                            'publication_attempt_cid': original_attempt['publication_attempt_cid'],
                            'result_manifest_cid': manifest['result_manifest_cid'],
                            'run_receipt_cid': receipt['receipt_identity_cid'],
                            'captured_run_cid': captured['captured_run_cid'],
                            'durable_result_binding_cids': [binding['durable_result_binding_cid']],
                        }
                        assert index['public_index_entry_cid'] == 'sha256:' + hashlib.sha256(
                            rfc8785.dumps(expected_index_body)).hexdigest()
                        assert fixture.queries == expected['source_queries']
                        commit_cases.append('original_index_intent_and_current_authority')
                        preflight_retirement_cases.append('original_commit_candidate_uses_same_retired_output_preflight')
                        publication_retirement_cases.append('original_commit_candidate_and_children_use_retired_parent_output')
                        if publisher_port:
                            publisher_expected = json.loads((root / 'scripts/fixtures/python-local-publisher-port.json').read_text())
                            store_input = copy({'store_authority_cid': facts['store_authority_cid']})
                            ticket += 1
                            publisher_ticket = ticket
                            fixture.inputs[publisher_ticket] = b''

                            def publisher_authority(fact):
                                # Expect the exact original request context. This
                                # fixture callback is not a product policy issuer.
                                assert fact.namespace_id == intent_facts['namespace_id']
                                assert fact.authority_scope_cid == CONFIGURATION['authority_scope_cid']
                                assert fact.run_definition_cid == original_request['run_definition_cid']
                                assert fact.publication_request_cid == original_request['publication_request_cid']
                                assert fact.public_index_entry_cid == (None if fact.stage == 'request' else index['public_index_entry_cid'])
                                fixture.publisher_seen.append(fact)
                                if fixture.publisher_revoke_after_auth:
                                    fixture.publisher_fence_ready = False
                                return fixture.publisher_answer

                            callbacks = _PublisherCallbacks(lambda: fixture.publisher_fence_ready,
                                                            publisher_authority)
                            fixture.publisher_bridge._inputs[publisher_ticket] = _PhysicalInput(
                                b'', lambda: True, lambda _: True, callbacks)
                            port = call('publisher', 'reserve', preflight, store_input, publisher_ticket,
                                        128 * 8192 + 4096 + sys.getsizeof(callbacks) +
                                        sys.getsizeof(fixture.publisher_bridge._inputs[publisher_ticket]))
                            assert port > 0
                            assert_status('publisher', 'install', 0, port, configuration)
                            assert fixture.publisher_seen == []
                            for stage in publisher_expected['stage_ordinals']:
                                assert_status('publisher', 'authorize', 0, port, configuration, stage,
                                              0 if stage == 0 else value)
                            assert [fact.stage for fact in fixture.publisher_seen] == publisher_expected['stages']
                            publisher_cases.append('original_six_facts_and_owner_generated_index_all_stages')
                            before = len(fixture.publisher_seen)
                            assert_status('publisher', 'authorize', -32, port, denied_configuration, 0, 0)
                            assert_status('publisher', 'authorize', -2, port, configuration, 1, value + 100000)
                            assert len(fixture.publisher_seen) == before
                            publisher_cases.append('current_run_source_and_foreign_index_refuse_before_callback')
                            fixture.publisher_answer = False
                            assert_status('publisher', 'authorize', -35, port, configuration, 0, 0)
                            fixture.publisher_answer = None
                            assert_status('publisher', 'authorize', -36, port, configuration, 0, 0)
                            fixture.publisher_answer = True
                            publisher_cases.append('independent_denial_and_unknown_do_not_cache_or_resend')
                            fixture.publisher_revoke_after_auth = True
                            assert_status('publisher', 'authorize', -32, port, configuration, 0, 0)
                            fixture.publisher_revoke_after_auth = False
                            before = len(fixture.publisher_seen)
                            assert_status('publisher', 'authorize', -32, port, configuration, 0, 0)
                            assert len(fixture.publisher_seen) == before
                            fixture.publisher_fence_ready = True
                            publisher_cases.append('authority_revocation_during_callback_is_fenced_afterwards')
                            assert fixture.call('close', store_input) == -9
                            allocated = fixture.call('allocated')
                            fixture.cleanup_ready = False
                            assert_status('publisher', 'close', -9, port)
                            assert fixture.call('allocated') == allocated
                            assert_status('publisher', 'authorize', -5, port, configuration, 0, 0)
                            assert fixture.call('close', store_input) == -9
                            fixture.cleanup_ready = True
                            fixture.stop_ready = False
                            assert_status('publisher', 'close', -9, port)
                            assert fixture.call('close', store_input) == -9
                            fixture.stop_ready = True
                            assert_status('publisher', 'close', 0, port)
                            assert_status('publisher', 'close', -2, port)
                            assert fixture.call('close', store_input) == 0
                            del fixture.publisher_bridge._inputs[publisher_ticket]
                            publisher_cases.append('same_transport_cleanup_then_original_input_borrow_stop_retry')
                            assert fixture.queries == expected['source_queries']
                            assert proposal['request'] == preflight_body['request']
                            assert proposal['attempt'] == preflight_body['attempt']
                            publisher_cases.append('no_source_compute_retry_or_store_commit_acknowledgement')
                            assert publisher_cases == publisher_expected['cases'][:-1]

                    loan, input_handle = binding_loan(facts)
                    assert_status('result_binding', 'produce', 0, loan, configuration)
                    assert_status('publication', 'close', -9, value)
                    if payload_request:
                        assert payload_child is not None and payload_input is not None
                        assert_status('payload_request', 'produce', -5, payload_child, configuration)
                        assert_status('payload_request', 'close', 0, payload_child)
                        assert fixture.call('close', payload_input) == 0
                        assert fixture.queries == expected['source_queries']
                        payload_request_cases.append('parent_close_keeps_child_without_source_compute_reexecution')
                        assert payload_request_cases == payload_expected['cases']
                    assert_status('result_binding', 'produce', -5, loan, configuration)
                    assert_status('result_binding', 'close', 0, loan)
                    assert fixture.call('close', input_handle) == 0
                    assert fixture.queries == expected['source_queries']
                    binding_cases.append('parent_close_retains_child_without_source_compute_replay')
                    if commit_candidate:
                        assert_status('publication_commit_export', 'produce', -5, commit_export, configuration)
                        if commit_index_key:
                            assert_status('publication_commit_export', 'produce_index_key', -5, commit_export, configuration)
                            assert fixture.queries == expected['source_queries']
                            commit_index_key_cases.append('parent_close_refuses_key_without_reexecution')
                            assert commit_index_key_cases == key_expected['cases']

                        if commit_materials:
                            assert_status('publication_commit_export', 'count', -5, value, configuration)
                            assert fixture.queries == expected['source_queries']
                            commit_material_cases.append('parent_close_refuses_count_without_reexecution')
                            assert commit_material_cases == material_expected['cases']
                        reserved = fixture.call('reserved')
                        fixture.cleanup_ready = False
                        assert_status('publication_commit_export', 'close', -9, commit_export)
                        assert fixture.call('reserved') == reserved
                        assert_status('publication', 'close', -9, value)
                        fixture.cleanup_ready = True
                        assert_status('publication_commit_export', 'close', 0, commit_export)
                        commit_cases.append('candidate_parent_pin_and_same_cleanup_retry')
                if quantum == 100:
                    # Closing parents seals them but retains custody until the
                    # same child output and reader cleanup both succeed.
                    assert call('result', 'close', result) == -9
                    assert call('source_publication', 'close', source_pin) == -9
                    preflight_retirement_cases.append('source_close_retains_original_pin_after_transport_retirement')
                    assert_status('publication', 'finish', -32, value, configuration)
                if commit_candidate and quantum == 7:
                    fixture.stop_ready = False
                fixture.cleanup_ready = False
                reserved = fixture.call('reserved')
                assert_status('publication', 'close', -9, value)
                assert fixture.call('reserved') == reserved
                fixture.cleanup_ready = True
                if commit_candidate and quantum == 7:
                    fixture.stop_ready = True
                assert_status('publication', 'close', 0, value)
                if commit_candidate and quantum == 7:
                    assert fixture.call('close', commit_input) == 0
                    publication_retirement_cases.append('full_close_returns_same_original_input_borrow_after_output_retirement')
                    assert publication_retirement_cases == retirement['cases']
                assert call('compute', 'configured', compute) == 0
                publication_cases.append('quantum_' + str(quantum) + '_exact_snapshot_manifest_receipt_capture_and_cleanup')
            assert call('run', 'close_configuration', denied_configuration) == 0
            publication_cases.extend(['revocation_before_and_after_cached_finish_refused',
                                      'original_authoring_journal_source_and_model_evidence_separated',
                                      'parent_close_retains_child_until_same_handle_cleanup',
                                      'original_source_and_compute_not_replayed'])
        assert call('task', 'close', tasks[1]) == -9
        assert call('result', 'reserve', tasks[1], 0) == -2
        assert call('result', 'close', result) == 0
        for task in reversed(tasks):
            assert call('task', 'close', task) == 0
        assert call('compute', 'close', compute) == -9
        fixture.cleanup_ready = False
        # Output is already retired. The original input reader's physical
        # stop, rather than former output cleanup, keeps this borrow pending.
        fixture.stop_ready = False
        if publisher_port:
            # Reserve a new transport before the original parent begins close.
            # No permission can be installed once that original parent closes.
            publisher_parent_input = copy({'store_authority_cid': facts['store_authority_cid']})
            ticket += 1
            fixture.inputs[ticket] = b''
            publisher_parent_child = call('publisher', 'reserve', preflight, publisher_parent_input,
                                          ticket, 128 * 8192 + 8192)
            assert publisher_parent_child > 0
        reserved = fixture.call('reserved')
        assert_status('publication_preflight', 'close', -9, preflight)
        assert fixture.call('reserved') == reserved
        assert_status('source_publication', 'close', -9, source_pin)
        if publisher_port:
            assert_status('publisher', 'install', -2, publisher_parent_child, configuration)
            assert fixture.call('close', publisher_parent_input) == -9
            fixture.cleanup_ready = True
            fixture.stop_ready = True
            assert_status('publisher', 'close', 0, publisher_parent_child)
            assert fixture.call('close', publisher_parent_input) == 0
            publisher_cases.append('original_preflight_close_waits_for_same_transport_custody')
            assert publisher_cases == publisher_expected['cases']
        fixture.cleanup_ready = True
        fixture.stop_ready = False
        assert_status('publication_preflight', 'close', -9, preflight)
        fixture.stop_ready = True
        assert_status('publication_preflight', 'close', 0, preflight)
        assert fixture.call('close', preflight_inputs[preflight]) == 0
        assert fixture.cleanups[preflight_output_tickets[preflight]] == 2
        preflight_retirement_cases.append('full_close_returns_same_original_input_borrow_after_tasks')
        retirement_expected = json.loads((root / 'scripts/fixtures/python-local-preflight-output-retirement.json').read_text())
        expected_retirement_cases = [name for name in retirement_expected['cases']
                                     if (commit_candidate or name != 'original_commit_candidate_uses_same_retired_output_preflight')
                                     and (final_publication or name != 'source_close_retains_original_pin_after_transport_retirement')]
        assert preflight_retirement_cases == expected_retirement_cases
        assert_status('source_publication', 'close', 0, source_pin)
        assert fixture.queries == 3
        preflight_cases.append('original_source_pin_and_same_borrow_cleanup_retry')
        if source_publication:
            source_cases.append('source_child_pins_parent_until_explicit_close')
        assert call('compute', 'close', compute) == 0
    root_before_cleanup = fixture.exports['actql_workspace_root_reserved'](fixture.store, fixture.nonce)
    # Fixed Wasm memory + physical DuckDB workspace + full transfer pool.
    base_execution = 16_777_216 + 67_108_864 + 8_388_608
    assert root_before_cleanup > base_execution
    fixture.native_stop_ready = False
    assert call('source', 'close_attempt', fixture.attempt) == -9
    assert fixture.exports['actql_workspace_root_reserved'](fixture.store, fixture.nonce) == root_before_cleanup
    fixture.native_stop_ready = True
    fixture.native_cleanup_ready = False
    assert call('source', 'close_attempt', fixture.attempt) == -9
    assert fixture.exports['actql_workspace_root_reserved'](fixture.store, fixture.nonce) == root_before_cleanup
    fixture.native_cleanup_ready = True
    assert call('source', 'close_attempt', fixture.attempt) == 0
    assert fixture.exports['actql_workspace_root_reserved'](fixture.store, fixture.nonce) == base_execution
    assert call('source', 'close_configuration', source) == 0
    assert call('run', 'close_physical_start', start) == 0
    assert call('run', 'close', run) == 0
    assert call('run', 'close_configuration', configuration) == 0
    assert call('program', 'close_preparation', preparation) == 0
    assert call('program', 'close_environment', environment) == 0
    assert fixture.exports['actql_workspace_close'](fixture.store, fixture.nonce, workspace) == 0
    assert fixture.call('close_pool') == 0
    assert fixture.call('reserved') == 0
    assert fixture.exports['actql_workspace_root_reserved'](
        fixture.store, fixture.nonce) == 16_777_216, 'Live Store memory is retained until physical disposal'
finally:
    if fixture.view is not None:
        fixture.view.close()
    if fixture.connection is not None:
        fixture.connection.close()
    fixture.close()
print(json.dumps({'module_sha256': hashlib.sha256(module).hexdigest(),
                  'library_sha256': library_digest, 'success': True,
                  'explicit_authored_view': explicit_view,
                  'normalization_completion_free': explicit_view,
                  'scope': ('private_unmetered_native_cleanup_boundary' if cleanup_only
                            else 'private_unmetered_native_compute_result_boundary'),
                  'execution_bytes': 536_870_912,
                  'retained_bytes': 536_870_912 if inventory_root else 200_000_000,
                  'checked_inventory': inventory, 'source_queries': fixture.queries,
                  'public_local_acceptance': False, 'durable_run_acceptance': False,
                  'default_fuel_acceptance': False,
                  'global_memory_accounting': False,
                  'source_publication_cases': source_cases,
                  'result_publication_cases': publication_cases,
                  'result_binding_cases': binding_cases,
                  'publication_preflight_cases': preflight_cases,
                  'preflight_retirement_cases': preflight_retirement_cases,
                  'publication_retirement_cases': publication_retirement_cases,
                  'commit_candidate_cases': commit_cases,
                  'commit_material_cases': commit_material_cases,
                  'commit_index_key_cases': commit_index_key_cases,
                  'payload_request_cases': payload_request_cases,
                  'payload_replay_cases': payload_replay_cases,
                  'payload_record_cases': payload_record_cases,
                  'payload_reservation_cases': payload_reservation_cases,
                  'payload_writing_cases': payload_writing_cases,
                  'payload_allocation_cases': payload_allocation_cases,
                  'payload_sealed_cases': payload_sealed_cases,
                  'payload_names_cases': payload_names_cases,
                  'payload_staging_cases': payload_staging_cases,
                  'payload_finalization_cases': payload_finalization_cases,
                  'payload_reader_cases': payload_reader_cases,
                  'payload_binding_cases': payload_binding_cases,
                  'publisher_port_cases': publisher_cases,
                  'cases': (['real_duckdb_owned_read_view', 'two_receipt_completion',
                             'pool_close_retains_native_custody', 'native_stop_and_cleanup_retry',
                             'native_capacity_retained_until_cleanup', 'formal_private_release']
                            if cleanup_only else ['real_duckdb_owned_read_view', 'same_native_capture',
                            'two_checked_tasks', 'execution_not_finalization',
                            'checked_named_result', 'foreign_producer_refusal',
                            'parent_pin_retention', 'close_seals_reserved_chunk',
                            'lost_chunk_acknowledgement', 'exact_independent_result',
                            'source_non_reexecution', 'native_stop_and_cleanup_retry',
                            'native_capacity_retained_until_cleanup', 'formal_private_release'])}))
