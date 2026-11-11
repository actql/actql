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
  let first = issue_client_effect_local_result_definition(
    owner, 0, "out", 4096, 16, 4,
  ).unwrap()
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
