import {connect, open, type HostCapacityPolicy, type HostLookupExecutionPolicy} from '@actql/node';
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
void connect({mode: 'local', owner: 'local', installation: {sourceNamespace: 'queries'}});
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only', authenticate: () => 'owner', sourceNamespace: 'queries'});
// @ts-expect-error Completeness is established by the Host, not a caller boolean.
void connect({mode: 'local', owner: 'local', installation: {sourceNamespace: {name: 'queries', complete: true}}});
// @ts-expect-error A partial map is not a complete capacity policy.
void connect({mode: 'local', owner: 'local', installation: {hostCapacityPolicy: {max_effect_items: 1}}});
// @ts-expect-error Capacity values are numeric contract fields.
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only', authenticate: () => 'owner', hostCapacityPolicy: {...policy, max_effect_items: '1'}});
// @ts-expect-error A caller cannot mutate the selected policy through its public type.
policy.max_effect_items = 2;

void connect({mode: 'local', owner: 'local', installation: {sourceSelectorNamespace: 'registrations'}});
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only', authenticate: () => 'owner', sourceSelectorNamespace: 'registrations'});
// @ts-expect-error Namespace completeness is not a caller-supplied success flag.
void connect({mode: 'local', owner: 'local', installation: {sourceSelectorNamespace: {name: 'registrations', complete: true}}});

const lookup: HostLookupExecutionPolicy = {
  version: 'actql-lookup-execution-policy/0.1', max_network_attempts_per_request: 3,
  max_request_bytes_per_attempt: 4096, max_total_request_bytes: 32768,
  max_total_response_bytes: 32768, max_total_decoded_response_bytes: 32768,
  max_total_duration_ms: 30000,
};
void connect({mode: 'local', owner: 'local', installation: {hostLookupExecutionPolicy: lookup}});
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only', authenticate: () => 'owner', hostLookupExecutionPolicy: lookup});
// @ts-expect-error Lookup ceilings are a complete closed contract, not a partial map.
void connect({mode: 'local', owner: 'local', installation: {hostLookupExecutionPolicy: {max_total_request_bytes: 1}}});
// @ts-expect-error A caller cannot mutate the captured policy through its public type.
lookup.max_total_response_bytes = 1;

// A Host supplies any admitted policy original; these compile-only values do
// not establish a classification, source permission or execution admission.
declare const admittedPolicyCid: string | undefined;
void connect({mode: 'local', installation: {
  async verifyRequestValuePolicy(subject, {signal}) {
    signal?.throwIfAborted();
    const sourceRef: string = subject.source_ref;
    void sourceRef;
    // @ts-expect-error Checked subjects cannot be replaced by the callback.
    subject.request.selector = 'replacement';
    return undefined;
  },
}});
void open({installation: {verifyRequestValuePolicy: () => admittedPolicyCid}});
// @ts-expect-error A classification object is not an admitted policy CID.
void connect({mode: 'local', installation: {verifyRequestValuePolicy: () => ({classification: 'public'})}});
// @ts-expect-error A boolean Promise cannot acknowledge policy verification.
void open({installation: {verifyRequestValuePolicy: async () => true}});

// Finite source-free runtime work is a Host installation selection, distinct
// from the normative capacity contract and compiler/check work.
void open({installation: {sourceFreeMaxWork: 30000000}});
void connect({mode: 'local', installation: {sourceFreeMaxWork: 30000000}});
void openInstalledRemoteHttpHost({directory: '/tmp/typecheck-only',
  authenticate: () => 'owner', sourceFreeMaxWork: 30000000});
// @ts-expect-error Work selection is a numeric signed-Int boundary, not text.
void open({installation: {sourceFreeMaxWork: '30000000'}});
