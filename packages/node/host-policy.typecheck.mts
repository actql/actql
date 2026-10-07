import {connect, type HostCapacityPolicy} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
const policy: HostCapacityPolicy = {
  "max_aggregate_array_items": 1000,
  "max_artifact_bytes": 1000,
  "max_artifact_rows": 1000,
  "max_effect_items": 1000,
  "max_graph_input_edges": 1000,
  "max_graph_input_nodes": 1000,
  "max_graph_output_rows": 1000,
  "max_graph_paths": 1000,
  "max_infer_items": 1000,
  "max_model_input_tokens_per_item": 1000,
  "max_model_request_bytes_per_item": 1000,
  "max_model_total_duration_ms": 1000,
  "max_nested_value_bytes": 1000,
  "max_nested_value_depth": 1000,
  "max_relation_output_rows": 1000,
  "max_temporal_matches_per_key": 1000,
  "max_temporal_output_rows": 1000,
  "version": "actql-capacity-host-policy/0.1"
};
void connect({mode: 'local', owner: 'local', installation: {hostCapacityPolicy: policy}});
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only', authenticate: () => 'owner', hostCapacityPolicy: policy});
// @ts-expect-error A partial map is not a complete capacity policy.
void connect({mode: 'local', owner: 'local', installation: {hostCapacityPolicy: {max_effect_items: 1}}});
// @ts-expect-error Capacity values are numeric contract fields.
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only', authenticate: () => 'owner', hostCapacityPolicy: {...policy, max_effect_items: '1'}});
// @ts-expect-error A caller cannot mutate the selected policy through its public type.
policy.max_effect_items = 2;
