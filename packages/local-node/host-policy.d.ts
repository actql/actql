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
