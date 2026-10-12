/** Exact checked request facts, available only to a trusted installed Host.
 * These facts are not a public credential, policy assertion or send permit. */
export type HostRequestValuePolicySubject = Readonly<{
  program_cid: string;
  parameters_cid: string;
  stage: number;
  input: number;
  source_ref: string;
  source_view_contract_cid: string;
  request_cid: string;
  request: Readonly<Record<string, HostRequestValuePolicyValue>>;
  origins: Readonly<Record<string, 'literal' | Readonly<{
    origin: 'default' | 'supplied'; parameter: string;
  }>>>;
}>;
export type HostRequestValuePolicyValue = null | boolean | number | string |
  readonly HostRequestValuePolicyValue[] |
  {readonly [name: string]: HostRequestValuePolicyValue};
/** Verify every actual value contributor before returning an already admitted
 * policy CID. Undefined preserves unknown provenance. Source response policy,
 * value shape and equal values do not establish verification. Source access,
 * Model egress and approvals remain independent. Recovery must establish the
 * same original correspondence rather than infer it from an equal CID. */
export type HostRequestValuePolicyVerifier = (subject: HostRequestValuePolicySubject,
  options: Readonly<{signal?: AbortSignal}>) =>
  string | undefined | Promise<string | undefined>;

/** Explicit finite keyed lookup policy. Omission leaves lookup unresolved. */
export type HostLookupExecutionPolicy = Readonly<{
  version: 'actql-lookup-execution-policy/0.1';
  max_network_attempts_per_request: number;
  max_request_bytes_per_attempt: number;
  max_total_request_bytes: number;
  max_total_response_bytes: number;
  max_total_decoded_response_bytes: number;
  max_total_duration_ms: number;
}>;

/** Complete existing capacity contract. Runtime admission enforces safe positive integers. */
export type HostCapacityPolicy = Readonly<{
  max_graph_construction_input_rows?: number;
  max_graph_construction_nodes?: number;
  max_graph_construction_edges?: number;
  max_aggregate_array_items: number;
  max_aggregate_string_bytes?: number;
  max_analytic_frame_memberships?: number;
  max_analytic_input_wire_bytes?: number;
  max_analytic_output_wire_bytes?: number;
  max_analytic_partition_wire_bytes?: number;
  max_artifact_bytes: number;
  max_artifact_rows: number;
  max_effect_items: number;
  max_graph_input_edges: number;
  max_graph_input_nodes: number;
  max_graph_output_rows: number;
  max_graph_paths: number;
  max_infer_items: number;
  max_model_input_tokens_per_item: number;
  max_model_request_bytes_per_item: number;
  max_model_total_duration_ms: number;
  max_nested_value_bytes: number;
  max_nested_value_depth: number;
  max_relation_output_rows: number;
  max_temporal_matches_per_key: number;
  max_temporal_output_rows: number;
  version: "actql-capacity-host-policy/0.1";
}>;
