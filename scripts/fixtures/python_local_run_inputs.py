"""Independently authored Local Run acceptance inputs, never product output."""
import json


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
AQL = 'WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer'


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
