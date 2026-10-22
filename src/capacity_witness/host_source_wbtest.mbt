///|
fn typed_host_source_policy() -> @policy.Policy {
  let text = "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
  let bytes = @utf8.encode(text)
  @policy.admit(bytes, "sha256:" + @sha.hex(bytes), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn typed_host_source_fixture() -> WireWitness {
  create_host_source(
    @policy.ceiling(typed_host_source_policy(), "max_artifact_rows").unwrap(),
    @arithmetic.Rows,
    @law.admit("actql.host.artifact-rows").unwrap(),
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
fn typed_host_source_text(
  w : WireWitness,
) -> String raise @encode.EncodeFailure {
  let out = @encode.writer(4096, 100, 4)
  emit(w, out)
  @encode.finish(out)
}

///|
fn typed_host_source_candidate(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 100,
    max_depth: 4,
    max_string_bytes: 4096,
    max_total_string_bytes: 4096,
  }).unwrap()
}

///|
test "generated Host source has a typed original and the old fixed wire identity" {
  let w = typed_host_source_fixture()
  assert_true(w.body is HostSource(_))
  assert_eq(
    w.cid,
    "sha256:0e2535b7ccbbbd1d573be32f28ad6a864d3d52563c4b766ab00ad0729462a4f5",
  )
  let body = typed_host_source_text(w)
  let external = admit(@utf8.encode(body), w.cid, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
  assert_true(external.body is Parsed(_))
  assert_true(same_witness_body(typed_host_source_candidate(body), w))
  assert_true(same_witness_body(typed_host_source_candidate(body), external))
}

///|
test "external candidates cannot hide changed fields behind a generated Host CID" {
  let w = typed_host_source_fixture()
  let text = typed_host_source_text(w)
  for
    changed in [
      text.replace(old="\"value\":1", new="\"value\":2"),
      text.replace(old="\"unit\":\"rows\"", new="\"unit\":\"bytes\""),
      text.replace(
        old="\"op\":\"source\"",
        new="\"extra\":true,\"op\":\"source\"",
      ),
      text.replace(old="max_artifact_rows", new="max_artifact_bytes"),
    ] {
    assert_false(same_witness_body(typed_host_source_candidate(changed), w))
    assert_true(
      admit(@utf8.encode(changed), w.cid, {
        max_bytes: 4096,
        max_nodes: 100,
        max_depth: 4,
      })
      is Err(_),
    )
  }
}
