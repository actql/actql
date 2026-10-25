///|
test "canonical optional capacity field remains admitted without input override" {
  let wire = "{\"max_aggregate_array_items\":1,\"max_aggregate_string_bytes\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
  let admitted = admit(
    @utf8.encode(wire),
    "sha256:f6a2a51860443826759ff7ddf672d73014452b928f5fe8fe46b81428f43417ec",
    { max_bytes: 10000, max_nodes: 100, max_depth: 3, },
  )
  assert_true(admitted is Ok(_))
}
