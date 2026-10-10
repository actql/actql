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
root = Path(__file__).resolve().parents[2]
module = Path(module_path).read_bytes()


class NativeFixture(PhysicalFixture):
    def __init__(self):
        self.connection = None
        self.view = None
        self.attempt = None
        self.workspace_ticket = 999
        self.queries = 0
        super().__init__(module, 1001, capacity=8_388_608, slots=64,
                         fuel=None, execution_bytes=536_870_912)

    def native_settled(self, handle):
        assert handle == self.attempt and self.view is not None
        return 0 if self.view.committed else 1

    def native_stopped(self, handle):
        assert handle == self.attempt and self.connection is not None
        return 0 if self.connection.stop_new_io() else 1

    def native_cleaned(self, handle):
        assert handle == self.attempt and self.view is not None
        return 0 if self.view.close() else 1

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
    assert fixture.exports['actql_host_abi_version'](fixture.store) == 11
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
    environment_wire = (root / 'scripts/fixtures/python-local-source-environment.json').read_text().strip()
    publication = {'environmentCid': 'sha256:b734cc90c9bffcd4098a70223685a9d9489992f426e861af2232e58261dd7424',
                   'aliases': [{'name': 'records', 'sourceRef': 'connector://crm/main/r#v',
                                'sourceViewContractCid': 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
                                'schemaContractCid': 'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4'}], 'tableWrites': []}
    environment = call('program', 'install_source_environment', copy({
        'environment': environment_wire, 'publication': encode(publication).decode()}))
    assert environment > 0
    program = {'version': 'actql/0.1', 'id': 'python-native-result', 'stages': [
        {'id': 'acquire', 'inputs': {'remote': {'connector': 'crm/main', 'resource': 'r'}},
         'steps': [{'filter': 'id > 2', 'as': 'filtered'}, {'select': ['id'], 'as': 'selected'}],
         'results': {'out': {'from': 'selected', 'fields': ['id']}}},
        {'id': 'compute', 'inputs': {'r': {'result': {'stage': 'acquire', 'result': 'out'}}},
         'steps': [{'derive': {'value': 'id + 1'}, 'as': 'derived'}, {'select': ['value'], 'as': 'selected'}],
         'results': {'out': {'from': 'selected', 'fields': ['value']}}},
        {'id': 'final', 'inputs': {'r': {'result': {'stage': 'compute', 'result': 'out'}}},
         'steps': [{'derive': {'next': 'value + 1'}, 'as': 'derived'}, {'select': ['next'], 'as': 'selected'}],
         'results': {'out': {'from': 'selected', 'fields': ['next']}}}],
        'results': {'answer': {'from': {'stage': 'final', 'result': 'out'}}}}
    preparation = call('program', 'reserve_preparation', environment, copy(program), 1)
    assert preparation > 0 and call('program', 'prepare', preparation) == 0
    assert call('program', 'prepared_results', preparation) == 1
    configuration = call('run', 'install_configuration', copy({**CONFIGURATION, 'account': account}))
    assert configuration > 0
    run = call('run', 'reserve', configuration, preparation, copy(REQUEST))
    assert run > 0 and call('run', 'prepare', run) == 0 and call('run', 'prepared', run) == 0
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
    fixture.attempt = call('source', 'reserve_attempt', source, start, copy({
        **read_account, 'attempt_nonce': 'native-result-private-fixture'}))
    assert fixture.attempt > 0 and call('source', 'start', fixture.attempt) == 0
    assert call('source', 'started', fixture.attempt) == 0
    fixture.view = fixture.connection.begin_read_view()
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
    compute = call('compute', 'reserve', fixture.attempt, copy({**read_account, **bodies}))
    assert compute > 0 and call('compute', 'configure', compute) == 0
    assert call('compute', 'configured', compute) == 0
    tasks = []
    for _ in range(2):
        task = call('task', 'reserve', compute, configuration)
        assert task > 0 and call('task', 'start', task) == 0
        assert call('task', 'started', task) == 0
        for _ in range(1000):
            assert call('task', 'feed', task, 1) == 0
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
    assert call('task', 'close', tasks[1]) == -9
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
    assert call('result', 'close', result) == 0
    for task in reversed(tasks):
        assert call('task', 'close', task) == 0
    assert call('compute', 'close', compute) == 0
    assert call('source', 'close_attempt', fixture.attempt) == 0
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
                  'scope': 'private_unmetered_native_compute_result_boundary',
                  'execution_bytes': 536_870_912, 'source_queries': fixture.queries,
                  'public_local_acceptance': False, 'durable_run_acceptance': False,
                  'default_fuel_acceptance': False,
                  'global_memory_accounting': False,
                  'cases': ['real_duckdb_owned_read_view', 'same_native_capture',
                            'two_checked_tasks', 'execution_not_finalization',
                            'checked_named_result', 'foreign_producer_refusal',
                            'parent_pin_retention', 'close_seals_reserved_chunk',
                            'lost_chunk_acknowledgement', 'exact_independent_result',
                            'source_non_reexecution', 'formal_private_release']}))
