///|
// Real checked Program and local Definitions; no runtime Artifact, input pin,
// Model/Source execution, public publication or backing acceptance is claimed.
test "public Result aliases select their own local definition even when one task is shared" {
  let (document, environment, limits) = client_composed_effect_base_fixture()
  let document = document
    .replace(
      old="\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"value\"]}}",
      new="\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"value\"]},\"other\":{\"from\":\"selected\",\"fields\":[\"value\"]}}",
    )
    .replace(
      old="\"results\":{\"published\":{\"from\":{\"stage\":\"source\",\"result\":\"out\"}}}",
      new="\"results\":{\"published\":{\"from\":{\"stage\":\"source\",\"result\":\"out\"}},\"second\":{\"from\":{\"stage\":\"source\",\"result\":\"other\"}}}",
    )
  let owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  assert_eq(@strategy.graph_result_count(graph), 2)
  assert_eq(
    @strategy.graph_result_task(graph, 0),
    @strategy.graph_result_task(graph, 1),
  )
  let geometry = client_effect_local_result_definition_construction_geometry(
    owner, 0, "out", 4096, 16, 4,
  ).unwrap()
  assert_eq((geometry.nodes, geometry.fields, geometry.depth), (5, 4, 1))
  let capacity = client_effect_local_result_definition_issuer_capacity(geometry).unwrap()
  let first = issue_client_effect_local_result_definition(
    owner, 0, "out", 4096, 16, 4,
  ).unwrap()
  // This fixture is ASCII and the issuer uses the same fixed-width self CID.
  assert_eq(first.wire.length(), geometry.bytes)
  assert_eq(first.cid.length(), 71)
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  assert_eq(retained, 96L + 2L * (first.wire.length() + 71).to_int64())
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) > retained,
  )
  let second = issue_client_effect_local_result_definition(
    owner, 0, "other", 4096, 16, 4,
  ).unwrap()
  assert_true(
    effect_local_result_definition_matches_public_result(owner, first, 0),
  )
  assert_false(
    effect_local_result_definition_matches_public_result(owner, second, 0),
  )
  assert_true(
    effect_local_result_definition_matches_public_result(owner, second, 1),
  )
  assert_false(
    effect_local_result_definition_matches_public_result(owner, first, 1),
  )
  assert_false(
    effect_local_result_definition_matches_public_result(owner, first, -1),
  )
  assert_false(
    effect_local_result_definition_matches_public_result(owner, second, 2),
  )
}
