"""Real Wasm common-Checker preparation; no Run acceptance or physical work."""
import hashlib
import json
from pathlib import Path
import sys
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


module = Path(sys.argv[1]).read_bytes()
fixture = PhysicalFixture(module, 303, capacity=65536, slots=16)


def program_call(name, *args):
    return fixture.exports['actql_program_' + name](fixture.store, fixture.nonce, *args)


try:
    config = fixture.copy(1, ENVIRONMENT, sys.getsizeof(ENVIRONMENT))
    environment = program_call('install_environment', config)
    assert environment > config
    for ticket, value, kind, minimum in [(2, PROGRAM, 1, 2), (3, AQL, 2, 1)]:
        payload = encode(value)
        source = fixture.copy(ticket, payload, sys.getsizeof(payload))
        prepared = program_call('prepare', environment, source, kind)
        assert prepared > source
        assert program_call('prepared_results', prepared) == 1
        assert program_call('prepared_tasks', prepared) >= minimum
        assert program_call('close_environment', environment) == -9
        assert fixture.call('close', source) == -9
        assert ticket not in fixture.cleanups
        assert program_call('close_preparation', prepared) == -9
        fixture.stop_ready = True
        assert program_call('close_preparation', prepared) == 0
        assert program_call('prepared_results', prepared) == -2
        fixture.cleanup_ready = True
        assert fixture.call('close', source) == 0
        fixture.stop_ready = False
        fixture.cleanup_ready = False
    # A rejected input owns custody as well; it is not converted to a prepared
    # empty Program and cannot release while its physical reader is pending.
    bad = encode({'version': 'actql/0.1', 'id': 'invalid', 'stages': []})
    source = fixture.copy(4, bad, sys.getsizeof(bad))
    rejected = program_call('prepare', environment, source, 1)
    assert rejected > source
    assert program_call('prepared_results', rejected) == -22
    assert program_call('prepared_tasks', rejected) == -22
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 65536
    fixture.stop_ready = True
    assert program_call('close_preparation', rejected) == 0
    assert program_call('close_environment', environment) == 0
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 65536
    fixture.cleanup_ready = True
    assert fixture.call('close_pool') == 0
    assert fixture.call('reserved') == 0
    assert len(fixture.cleanups) == 4
finally:
    fixture.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
                  'cases': ['structured_core_preparation', 'aql_core_preparation',
                            'input_borrow_custody', 'environment_lifetime',
                            'typed_rejection_custody', 'physical_stop_retry',
                            'cleanup_failure_reservation', 'final_settlement']}))
