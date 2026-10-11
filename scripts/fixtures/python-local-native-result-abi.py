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

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))
from actql_sdk._local_command import native_command
from actql_sdk._local_duckdb import DuckDBLibrary, DuckDBConnection, DuckDBTransferLimits


module_path, library_path, library_digest = sys.argv[1:4]
cleanup_only = sys.argv[4:] == ['--native-cleanup-only']
inventory_root = '--bounded-inventory-root' in sys.argv[4:]
source_publication = '--source-publication' in sys.argv[4:]
explicit_view = '--explicit-view' in sys.argv[4:]
final_publication = '--final-publication' in sys.argv[4:]
assert sys.argv[4:] in ([], ['--native-cleanup-only'], ['--bounded-inventory-root'],
                       ['--bounded-inventory-root', '--source-publication'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view'],
                       ['--bounded-inventory-root', '--source-publication', '--explicit-view', '--final-publication'])
source_cases = []
publication_cases = []
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


def copy(value):
    global ticket
    ticket += 1
    payload = value if isinstance(value, bytes) else encode(value)
    return fixture.copy(ticket, payload, sys.getsizeof(payload))


def call(family, name, *args):
    return fixture.exports['actql_' + family + '_' + name](fixture.store, fixture.nonce, *args)


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
    assert fixture.exports['actql_host_abi_version'](fixture.store) == 19
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
        if source_publication:
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
            if final_publication:
                for _ in range(10000):
                    assert call('source_publication', 'advance', source_pin, 100) == 0
                    if call('source_publication', 'progress', source_pin, 0) == 1:
                        break
                else:
                    raise AssertionError('Retained Source invocation did not complete')
                assert call('source_publication', 'finish', source_pin, configuration) == 0
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
            expected = json.loads((root / 'scripts/fixtures/python-local-result-publication.json').read_text())
            # Hash the independently frozen input, never a product response.
            assert 'sha256:' + hashlib.sha256(expected['retention_preimage'].encode()).hexdigest() == expected['retention_policy_cid']
            retention = json.loads(expected['retention_preimage'])
            retention['retention_policy_cid'] = expected['retention_policy_cid']
            retention_wire = json.dumps(retention, sort_keys=True, separators=(',', ':'))

            def publication_loan(**overrides):
                global ticket
                request = copy({'results': [result], 'retention': retention_wire,
                                'max_work': 1000000, 'max_workspace_slots': 100000,
                                **overrides})
                ticket += 1
                fixture.inputs[ticket] = b''
                value = call('publication', 'reserve', source_pin, request, ticket, 2097200)
                assert value > 0
                return value

            for supplied, code in ((None, -31), ([], -31), ([result, result], -2), ([tasks[0]], -2)):
                value = publication_loan(results=supplied)
                assert call('publication', 'prepare', value, configuration) == code
                assert call('publication', 'length', value) == -33
                assert call('publication', 'close', value) == 0
            publication_cases.append('null_empty_duplicate_foreign_result_inventory_refused')
            missing = copy({'retention': retention_wire, 'max_work': 100,
                            'max_workspace_slots': 100000})
            ticket += 1
            fixture.inputs[ticket] = b''
            value = call('publication', 'reserve', source_pin, missing, ticket, 2097200)
            assert value > 0
            assert call('publication', 'prepare', value, configuration) == -31
            assert call('publication', 'length', value) == -33
            assert call('publication', 'close', value) == 0
            publication_cases.append('absent_inventory_is_not_null_or_full_inventory')
            exhausted = publication_loan(max_work=1)
            assert call('publication', 'prepare', exhausted, configuration) == 0
            assert call('publication', 'finish', exhausted, configuration) == -7
            assert call('publication', 'advance', exhausted, configuration, 1) == 0
            assert call('publication', 'advance', exhausted, configuration, 1) == -32
            assert call('publication', 'progress', exhausted, 2) == 1
            assert call('publication', 'length', exhausted) == -33
            assert call('publication', 'close', exhausted) == 0
            assert call('compute', 'configured', compute) == 0
            publication_cases.append('unfinished_budget_refusal_retains_work_and_original_compute')
            denied_account = json.loads(account)
            denied_account['entries'][0]['outcome'] = 'deny'
            denied_configuration = call('run', 'install_configuration', copy({
                **CONFIGURATION, 'account': encode(denied_account).decode()}))
            assert denied_configuration > 0
            revoked = publication_loan()
            assert call('publication', 'prepare', revoked, configuration) == 0
            assert call('publication', 'prepare', revoked, denied_configuration) == -32
            assert call('publication', 'advance', revoked, denied_configuration, 7) == -32
            assert call('publication', 'length', revoked) == -33
            assert call('publication', 'close', revoked) == 0
            publication_cases.append('current_authority_checked_before_each_owner_yield')
            expected_work = expected_body = None
            for quantum in (7, 100):
                value = publication_loan()
                assert call('publication', 'prepare', value, configuration) == 0
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
                assert call('publication', 'finish', value, denied_configuration) == -32
                assert call('publication', 'length', value) == -33
                assert call('publication', 'finish', value, configuration) == 0
                assert call('publication', 'finish', value, denied_configuration) == -32
                assert call('publication', 'finish', value, configuration) == 0
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
                if quantum == 100:
                    # Closing parents seals them but retains custody until the
                    # same child output and reader cleanup both succeed.
                    assert call('result', 'close', result) == -9
                    assert call('source_publication', 'close', source_pin) == -9
                    assert call('publication', 'finish', value, configuration) == -32
                fixture.cleanup_ready = False
                reserved = fixture.call('reserved')
                assert call('publication', 'close', value) == -9
                assert fixture.call('reserved') == reserved
                fixture.cleanup_ready = True
                assert call('publication', 'close', value) == 0
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
        if source_publication:
            assert call('compute', 'close', compute) == -9
            assert call('source_publication', 'close', source_pin) == 0
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
