///|
test "funded single Model materials preserve original bytes and stop before execution projection" {
  let (_, allowed, definition, request) = selected_infer_original_fixture()
  let ordinary = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let seen : Array[String] = []
  let funded = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
    before_body=Some(fn(purpose, _, _, _) {
      seen.push(purpose)
      true
    }),
  ).unwrap()
  assert_eq(funded, ordinary)
  assert_eq(seen.filter(value => value == "model_execution"), [
    "model_execution",
  ])
  seen.clear()
  assert_true(
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request=Some(request),
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        purpose != "model_execution"
      }),
    )
    is Err(Input(MaterialsConstructionRefused("model_execution"))),
  )
  assert_eq(seen.last(), Some("model_execution"))
  assert_false(seen.contains("run_materials"))
}

///|
test "funded plural Model materials keep complete original inventory without graph reissuance" {
  let (_, allowed, definition, request) = plural_effect_infer_fixture()
  let compilation = allowed.compilation
  let expected = client_effect_original_infer_inputs(compilation)
    .unwrap()
    .unwrap()
  let seen : Array[String] = []
  let funded = client_effect_original_infer_inputs(
      compilation,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        true
      }),
    )
    .unwrap()
    .unwrap()
  assert_eq(funded, expected)
  assert_eq(seen, ["model_inventory", "model_execution", "model_execution"])
  let expected_materials = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  assert_eq(
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request=Some(request),
      before_body=Some((_, _, _, _) => true),
    ).unwrap(),
    expected_materials,
  )
  seen.clear()
  assert_true(
    client_effect_original_infer_inputs(
      compilation,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        false
      }),
    )
    is Err(Input(MaterialsConstructionRefused("model_inventory"))),
  )
  assert_eq(seen, ["model_inventory"])
  seen.clear()
  assert_true(
    client_effect_original_infer_inputs(
      compilation,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        purpose != "model_execution"
      }),
    )
    is Err(Input(MaterialsConstructionRefused("model_execution"))),
  )
  assert_eq(seen, ["model_inventory", "model_execution"])
  let first = compilation.compiled.infers[0]
  let substituted = { ..first, graph: { ..first.graph, }, }
  let copied = {
    ..compilation,
    compiled: {
      ..compilation.compiled,
      infers: [substituted, compilation.compiled.infers[1]],
    },
  }
  assert_true(
    client_effect_original_infer_inputs(
      copied,
      before_body=Some((_, _, _, _) => true),
    )
    is Err(Compilation(ForeignInferOwner)),
  )
}

///|
test "funded source-free policy admission keeps the same complete policy and refuses first" {
  let (base, environment, limits) = client_composed_effect_base_fixture()
  let document = base.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"seed\"},{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"value\"],\"name\":\"out.jsonl\",\"preserve_order\":true,\"bounds\":{\"max_rows\":2,\"max_bytes\":128}},\"as\":\"attachment\"},{\"derive\":{\"value\":{\"literal\":1}},\"as\":\"selected\"}],",
  )
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let bounds = run_materials_limits()
  let policy = serialization_plan_test_policy()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
    source_free_policy=Some(policy),
  ).unwrap()
  let expected = client_effect_original_source_free_policy_input(compilation)
    .unwrap()
    .unwrap()
  let seen : Array[String] = []
  assert_eq(
    client_effect_original_source_free_policy_input(
      compilation,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        true
      }),
    ).unwrap(),
    Some(expected),
  )
  assert_eq(seen, ["source_free_policy_read"])
  assert_eq(
    expected.0,
    @publication.captured_effect_dependency_body_cid(policy),
  )
  assert_eq(
    expected.1,
    @publication.captured_effect_dependency_body_json(policy),
  )
  seen.clear()
  assert_true(
    client_effect_original_source_free_policy_input(
      compilation,
      before_body=Some(fn(purpose, _, _, _) {
        seen.push(purpose)
        false
      }),
    )
    is Err(Input(MaterialsConstructionRefused("source_free_policy_read"))),
  )
  assert_eq(seen, ["source_free_policy_read"])
}
