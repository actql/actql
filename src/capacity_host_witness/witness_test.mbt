///|
fn policy(text : String) -> @policy.Policy {
  let bytes = @utf8.encode(text)
  @policy.admit(bytes, "sha256:" + @sha.hex(bytes), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn fixture() -> String {
  "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
}

///|
fn limits() -> @capacity_host_witness.Limits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 4, }
}

///|
test "fixed host witness max_aggregate_array_items" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_aggregate_array_items").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:4c7ae8cb395c5ec84af3eb3d0cf4ff7f9a893c10485c47e99fc82318904da156",
  )
  assert_eq(
    @capacity_host_witness.law_id(w),
    "actql.host.aggregate-array-items",
  )
  assert_eq(@capacity_host_witness.unit(w), @derivation.ArrayItems)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.aggregate-array-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_aggregate_array_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"array_items\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4c7ae8cb395c5ec84af3eb3d0cf4ff7f9a893c10485c47e99fc82318904da156\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_aggregate_array_items")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_artifact_bytes" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_artifact_bytes").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:4e239a9b0fb7df0afa291d763125f3e82ae0495f6bed6b8ed4c8dad74d38d6c1",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.artifact-bytes")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Bytes)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.artifact-bytes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_artifact_bytes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"bytes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4e239a9b0fb7df0afa291d763125f3e82ae0495f6bed6b8ed4c8dad74d38d6c1\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_artifact_bytes")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_artifact_rows" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_artifact_rows").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:0e2535b7ccbbbd1d573be32f28ad6a864d3d52563c4b766ab00ad0729462a4f5",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.artifact-rows")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Rows)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.artifact-rows\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_artifact_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:0e2535b7ccbbbd1d573be32f28ad6a864d3d52563c4b766ab00ad0729462a4f5\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_artifact_rows")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_effect_items" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_effect_items").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:a223a89ae11d24c9be60416dd5c35be6bdb2c01aed0705b4a83089fe87574e31",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.effect-items")
  assert_eq(@capacity_host_witness.unit(w), @derivation.EffectItems)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.effect-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_effect_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"effect_items\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a223a89ae11d24c9be60416dd5c35be6bdb2c01aed0705b4a83089fe87574e31\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_effect_items")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_graph_input_edges" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_graph_input_edges").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.graph-input-edges")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Edges)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_graph_input_edges")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_graph_input_nodes" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_graph_input_nodes").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.graph-input-nodes")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Nodes)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_graph_input_nodes")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_graph_output_rows" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_graph_output_rows").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:5f824a9498c4e9db05c8024e88f85fc829a962cce0a96a07672ee9587323d317",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.graph-output")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Rows)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:5f824a9498c4e9db05c8024e88f85fc829a962cce0a96a07672ee9587323d317\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_graph_output_rows")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_graph_paths" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_graph_paths").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:50d83be0393ba0390442d3a7e13d0b6242c18f61f4bc6d2a5ad510a132fe0663",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.graph-paths")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Paths)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-paths\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_paths\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"paths\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:50d83be0393ba0390442d3a7e13d0b6242c18f61f4bc6d2a5ad510a132fe0663\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_graph_paths")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_infer_items" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_infer_items").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:f632cb199d47a451c8941ab0efc540d193d41515c95b4fbedc6a6f74d9f096cb",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.infer-items")
  assert_eq(@capacity_host_witness.unit(w), @derivation.DistinctKeys)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.infer-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_infer_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"distinct_keys\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f632cb199d47a451c8941ab0efc540d193d41515c95b4fbedc6a6f74d9f096cb\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_infer_items")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_model_request_bytes_per_item" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_model_request_bytes_per_item").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:d58381703b0186b1c307070cd79c5732c3939a48639e13d117c91cfdca1333de",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.model-request-bytes")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Bytes)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.model-request-bytes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_model_request_bytes_per_item\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"bytes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d58381703b0186b1c307070cd79c5732c3939a48639e13d117c91cfdca1333de\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_model_request_bytes_per_item")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_nested_value_bytes" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_nested_value_bytes").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:b829c499a1f241813e7e31dd5a884d5fee4dcdfd9fc79e89bedb6d8827220688",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.nested-value-bytes")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Bytes)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.nested-value-bytes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_nested_value_bytes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"bytes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:b829c499a1f241813e7e31dd5a884d5fee4dcdfd9fc79e89bedb6d8827220688\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_nested_value_bytes")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_relation_output_rows" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_relation_output_rows").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.relation-output")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Rows)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_relation_output_rows")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_temporal_matches_per_key" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_temporal_matches_per_key").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.temporal-matches")
  assert_eq(@capacity_host_witness.unit(w), @derivation.MatchesPerKey)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"matches_per_key\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_temporal_matches_per_key")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "fixed host witness max_temporal_output_rows" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_temporal_output_rows").unwrap()
  let w = @capacity_host_witness.create(source, limits()).unwrap()
  assert_eq(
    @capacity_host_witness.cid(w),
    "sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a",
  )
  assert_eq(@capacity_host_witness.law_id(w), "actql.host.temporal-output")
  assert_eq(@capacity_host_witness.unit(w), @derivation.Rows)
  let output = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, output)
  assert_eq(
    @encode.finish(output),
    "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a\"}",
  )
  let retained = @capacity_host_witness.ceiling(w)
  assert_eq(@policy.ceiling_field(retained), "max_temporal_output_rows")
  assert_eq(@policy.ceiling_value(retained), 1L)
  assert_eq(@policy.cid(@policy.ceiling_policy(retained)), @policy.cid(p))
}

///|
test "non-witness policy quantities are not reinterpreted as available units" {
  let p = policy(fixture())
  for
    field in [
      "max_nested_value_depth", "max_model_input_tokens_per_item", "max_model_total_duration_ms",
    ] {
    assert_true(
      @capacity_host_witness.create(
        @policy.ceiling(p, field).unwrap(),
        limits(),
      )
      is Err(UnsupportedPolicyField(actual)) &&
      actual == field,
    )
  }
}

///|
test "equal values retain distinct fields and the complete selected policy identity" {
  let p = policy(fixture())
  let field = "max_artifact_rows"
  let a = @capacity_host_witness.create(
    @policy.ceiling(p, field).unwrap(),
    limits(),
  ).unwrap()
  let b = @capacity_host_witness.create(
    @policy.ceiling(p, "max_relation_output_rows").unwrap(),
    limits(),
  ).unwrap()
  assert_true(@capacity_host_witness.cid(a) != @capacity_host_witness.cid(b))
  let changed = policy(
    fixture().replace(old="\"max_graph_paths\":1", new="\"max_graph_paths\":2"),
  )
  let c = @capacity_host_witness.create(
    @policy.ceiling(changed, field).unwrap(),
    limits(),
  ).unwrap()
  assert_true(@capacity_host_witness.cid(a) != @capacity_host_witness.cid(c))
  assert_eq(
    @policy.ceiling_value(@capacity_host_witness.ceiling(a)),
    @policy.ceiling_value(@capacity_host_witness.ceiling(c)),
  )
}

///|
fn emits(
  w : @capacity_host_witness.Witness,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Bool {
  try {
    let output = @encode.writer(bytes, nodes, depth)
    @capacity_host_witness.emit(w, output)
    ignore(@encode.finish(output))
    true
  } catch {
    _ => false
  }
}

///|
test "construction bounds the preimage and emission independently bounds the complete witness" {
  let p = policy(fixture())
  let source = @policy.ceiling(p, "max_aggregate_array_items").unwrap()
  let exact : @capacity_host_witness.Limits = {
    max_bytes: 409,
    max_nodes: 14,
    max_depth: 2,
  }
  let w = @capacity_host_witness.create(source, exact).unwrap()
  assert_true(
    @capacity_host_witness.create(source, { ..exact, max_bytes: 408, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_host_witness.create(source, { ..exact, max_nodes: 13, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_host_witness.create(source, { ..exact, max_depth: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_host_witness.create(source, { ..exact, max_bytes: -1, })
    is Err(InvalidLimits),
  )
  assert_true(emits(w, 497, 15, 2))
  assert_false(emits(w, 496, 15, 2))
  assert_false(emits(w, 497, 14, 2))
  assert_false(emits(w, 497, 15, 1))
}
