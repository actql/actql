"""Real Wasm Run compilation custody; not durable acceptance or Compute."""
import hashlib
import json
from pathlib import Path
import sys
import wasmtime
from python_local_physical import PhysicalFixture


# Independent configuration and authored inputs. No product output generates
# either a source fixture or an expected diagnostic/result location.
ENVIRONMENT = b'{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}'
PROGRAM = {'version': 'actql/0.1', 'id': 'python.local.structured', 'stages': [
    {'id': 'seed', 'inputs': {}, 'steps': [
        {'values': {'schema': {'n': {'type': 'number', 'nullable': False}},
                    'rows': [{'n': 1}]}, 'as': 'data'}],
     'results': {'rows': {'from': 'data', 'fields': ['n']}}},
    {'id': 'compute', 'inputs': {'seed': {'result': {'stage': 'seed', 'result': 'rows'}}},
     'steps': [{'derive': {'value': 'n + 1'}, 'as': 'derived'},
               {'select': ['value'], 'as': 'selected'}],
     'results': {'rows': {'from': 'selected', 'fields': ['value']}}}],
    'results': {'answer': {'from': {'stage': 'compute', 'result': 'rows'}}}}
AQL = 'DATA seed = SELECT 1 AS n; FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer'


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


ACCOUNT = {'version': 'actql-execution-account-config/0.1',
           'account_id': 'local-account', 'entries': [{
               'entry_id': 'local-submission', 'outcome': 'allow',
               'principal': {'any_of': ['local-user']},
               'connection': {'any_of': ['python.local']},
               'resource': {'any_of': ['runs']},
               'operation': {'any_of': ['submit']}, 'exclusions': []}]}
CONFIGURATION = {'account': encode(ACCOUNT).decode('utf-8'),
                 'principal': 'local-user', 'connection': 'python.local',
                 'resource': 'runs', 'operation': 'submit',
                 'authority_scope_cid': 'sha256:' + 'b' * 64,
                 'context_cid': 'sha256:' + 'a' * 64,
                 'policy_cid': 'sha256:' + 'c' * 64, 'namespace': 'local'}
REQUEST = {'caller_request_id': 'original-submission', 'run_id': 'original-run',
           'created_at': '2026-10-10T00:00:00.000Z',
           'valid_until': '2099-01-01T00:00:00.000Z'}
module = Path(sys.argv[1]).read_bytes()
fixture = PhysicalFixture(module, 505, capacity=262144, slots=32, fuel=100000000)
ticket = 0


def copy(value):
    global ticket
    ticket += 1
    payload = value if isinstance(value, bytes) else encode(value)
    return fixture.copy(ticket, payload, sys.getsizeof(payload))


def call(family, name, *arguments):
    return fixture.exports['actql_' + family + '_' + name](
        fixture.store, fixture.nonce, *arguments)


try:
    environment = call('program', 'install_environment', copy(ENVIRONMENT))
    assert environment > 0
    config = call('run', 'install_configuration', copy(CONFIGURATION))
    assert config > 0
    prepared = []
    for original, kind in [(PROGRAM, 1), (AQL, 2)]:
        preparation = call('program', 'reserve_preparation', environment, copy(original), kind)
        assert preparation > 0
        assert call('program', 'prepare', preparation) == 0
        handle = call('run', 'reserve', config, preparation, copy(REQUEST))
        assert handle > 0
        assert call('run', 'prepared', handle) == -33
        reads = fixture.reads
        assert call('run', 'prepare', handle) == 0
        assert call('run', 'prepared', handle) == 0
        assert call('run', 'prepare', handle) == 0
        assert fixture.reads == reads
        assert call('program', 'close_preparation', preparation) == -9
        assert call('run', 'close_configuration', config) == -9
        assert call('run', 'close', handle) == -9
        fixture.stop_ready = True
        assert call('run', 'close', handle) == 0
        assert call('run', 'prepared', handle) == -2
        fixture.stop_ready = False
        prepared.append(preparation)

    # The Account Owner must evaluate the installed grant. An otherwise valid
    # policy/context identity is not a grant for a different principal.
    foreign = call('run', 'install_configuration', copy({**CONFIGURATION,
                                                        'principal': 'other-user'}))
    denied = call('run', 'reserve', foreign, prepared[0], copy(REQUEST))
    assert denied > 0
    assert call('run', 'prepare', denied) == 0
    assert call('run', 'prepared', denied) == -32
    assert call('run', 'install_configuration', copy({**CONFIGURATION,
                'account': encode({**ACCOUNT, 'unknown': True}).decode()})) == -30
    assert call('run', 'install_configuration', copy({**CONFIGURATION,
                                                     'unknown': True})) == -30
    assert call('run', 'reserve', config, 2147483647, copy(REQUEST)) == -2

    # Missing, NULL and unknown request fields remain malformed Host input;
    # they cannot become an empty or admitted Run, nor be implicitly retried.
    for request in [{key: value for key, value in REQUEST.items() if key != 'run_id'},
                    {**REQUEST, 'run_id': None}, {**REQUEST, 'unknown': True}]:
        handle = call('run', 'reserve', config, prepared[0], copy(request))
        assert handle > 0
        assert call('run', 'prepare', handle) == -31
        assert call('run', 'prepared', handle) == -33
        assert call('run', 'prepare', handle) == -33
        fixture.stop_ready = True
        assert call('run', 'close', handle) == 0
        fixture.stop_ready = False

    # Interrupt actual Wasm after the positive handle has reached the caller.
    # Missing outcome never implies unstarted work or permission to recompile.
    handle = call('run', 'reserve', config, prepared[0], copy(REQUEST))
    assert handle > 0
    held = fixture.call('allocated')
    fixture.store.set_fuel(5000)
    try:
        call('run', 'prepare', handle)
    except wasmtime.Trap:
        pass
    else:
        raise AssertionError('Expected an actual interrupted Run compilation')
    fixture.store.set_fuel(100000000)
    assert call('run', 'prepared', handle) == -33
    assert call('run', 'prepare', handle) == -33
    assert fixture.call('allocated') == held
    assert call('run', 'close', handle) == -9
    assert call('run', 'close_configuration', config) == -9
    assert call('program', 'close_preparation', prepared[0]) == -9
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 262144
    fixture.stop_ready = True
    assert call('run', 'close', handle) == 0
    assert call('run', 'close', denied) == 0
    for preparation in prepared:
        assert call('program', 'close_preparation', preparation) == 0
    assert call('run', 'close_configuration', config) == 0
    assert call('run', 'close_configuration', foreign) == 0
    assert call('program', 'close_environment', environment) == 0
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 262144
    fixture.cleanup_ready = True
    assert fixture.call('close_pool') == 0
    assert fixture.call('reserved') == 0
finally:
    fixture.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
                  'cases': ['structured_run_compilation', 'aql_run_compilation',
                            'account_subject_denial', 'closed_account_configuration',
                            'closed_host_configuration', 'unprepared_input_rejection',
                            'missing_null_unknown_request', 'parent_handle_lifetime',
                            'actual_compilation_trap', 'no_implicit_compilation_retry',
                            'cleanup_pending_same_reservation', 'final_settlement']}))
