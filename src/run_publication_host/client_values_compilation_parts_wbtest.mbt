///|
fn values_compilation_parts_prepared() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  prepare_effect_free_client_program(
    run_materials_document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "Values compilation parts retain the original checked components without reissuance" {
  let prepared = values_compilation_parts_prepared()
  let limits = run_materials_limits()
  let parts = issue_prepared_client_values_executable_plan_parts(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = issue_client_values_compilation_with_parts(
    prepared, parts, 100000, 10000, 100,
  ).unwrap()
  assert_true(physical_equal(compiled.owner, prepared))
  assert_eq(compiled.plan.transformations.length(), 0)
  assert_true(physical_equal(compiled.plan, parts.plan))
  assert_true(physical_equal(compiled.template, parts.template))
  assert_true(physical_equal(compiled.fragment, parts.fragment))
  // Standalone public issuers keep their existing bytes. Their independent
  // calls here are compatibility controls, not work of one compilation.
  let standalone = issue_prepared_client_values_executable_plan(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(parts.plan.wire, standalone.wire)
  assert_eq(parts.plan.cid, standalone.cid)
  assert_eq(parts.plan.fact_manifest_wire, standalone.fact_manifest_wire)
  assert_eq(
    @publication.run_evidence_value_json(parts.template),
    @publication.run_evidence_value_json(
      issue_prepared_source_free_client_bound_template(
        prepared,
        run_materials_manifests(),
        limits.sequence,
        100000,
        10000,
        100,
      ).unwrap(),
    ),
  )
  assert_eq(
    parts.fragment.wire,
    issue_prepared_client_values_fragment(
      prepared,
      0,
      limits.sequence,
      100000,
      10000,
      100,
    ).unwrap().wire,
  )
}

///|
test "Values compilation parts reject a CID-equal foreign checked owner" {
  let prepared = values_compilation_parts_prepared()
  let foreign = values_compilation_parts_prepared()
  assert_true(!physical_equal(prepared, foreign))
  assert_eq(
    prepared_client_identity(prepared),
    prepared_client_identity(foreign),
  )
  let parts = issue_prepared_client_values_executable_plan_parts(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    issue_client_values_compilation_with_parts(
      foreign, parts, 100000, 10000, 100,
    )
    is Err(Plan(Graph(UnsupportedGraph))),
  )
  let compiled = issue_client_values_compilation_with_parts(
    prepared, parts, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    issue_client_values_compiled_run(
      foreign,
      compiled,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    )
    is Err(ForeignOwner),
  )
}

///|
test "Values compilation parts preserve original preparation and encoding limits" {
  let prepared = values_compilation_parts_prepared()
  for maximum in [0, -1] {
    assert_true(
      issue_prepared_client_values_compilation(
        prepared,
        run_materials_manifests(),
        run_materials_limits().sequence,
        maximum,
        64,
        100000,
        10000,
        100,
      )
      is Err(Plan(InvalidLimits)),
    )
  }
  assert_true(
    issue_prepared_client_values_compilation(
      prepared,
      run_materials_manifests(),
      run_materials_limits().sequence,
      32,
      64,
      1,
      10000,
      100,
    )
    is Err(_),
  )
}

///|
fn result_material_prepared() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"result-material","stages":[{"id":"source","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"},{"id":2,"label":"second"}]}}],"results":{"rows":{"from":"v","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "material retains the actual same-original Result Plan without another full issuer" {
  let value = result_material_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    value,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(graph.transformations.length(), 1)
  let calls = Ref(0)
  let plan = client_material_result_plan(
    value,
    0,
    graph.result_plans,
    100000,
    10000,
    100,
    (owner, result, bytes, nodes, depth) => {
      calls.val += 1
      issue_prepared_client_result_plan(owner, result, bytes, nodes, depth)
    },
  ).unwrap()
  assert_eq(calls.val, 0)
  assert_true(physical_equal(plan, graph.result_plans[0]))
}

///|
test "material rebuilds a CID-equal Result Plan from a different original owner" {
  let original = result_material_prepared()
  let foreign = result_material_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    original,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let calls = Ref(0)
  let plan = client_material_result_plan(
    foreign,
    0,
    graph.result_plans,
    100000,
    10000,
    100,
    (owner, result, bytes, nodes, depth) => {
      calls.val += 1
      issue_prepared_client_result_plan(owner, result, bytes, nodes, depth)
    },
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(plan.cid, graph.result_plans[0].cid)
  assert_true(!physical_equal(plan, graph.result_plans[0]))
}

///|
test "material changed codec bounds select the original full Result issuer" {
  let value = result_material_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    value,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let calls = Ref(0)
  let issue = (owner, result, bytes, nodes, depth) => {
    calls.val += 1
    issue_prepared_client_result_plan(owner, result, bytes, nodes, depth)
  }
  let plan = client_material_result_plan(
    value,
    0,
    graph.result_plans,
    99999,
    10000,
    100,
    issue,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(plan.cid, graph.result_plans[0].cid)
  assert_true(!physical_equal(plan, graph.result_plans[0]))
  assert_true(
    client_material_result_plan(value, 0, graph.result_plans, 1, 1, 1, issue)
    is Err(_),
  )
  assert_eq(calls.val, 2)
}

///|
test "material a different Result cannot reuse the retained original Plan" {
  let value = result_material_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    value,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let calls = Ref(0)
  assert_true(
    client_material_result_plan(
      value,
      1,
      graph.result_plans,
      100000,
      10000,
      100,
      (owner, result, bytes, nodes, depth) => {
        calls.val += 1
        issue_prepared_client_result_plan(owner, result, bytes, nodes, depth)
      },
    )
    is Err(MissingResult),
  )
  assert_eq(calls.val, 1)
}

///|
test "direct material keeps the original Result Plan without full reissuance" {
  let value = values_compilation_parts_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    value,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(graph.transformations.length(), 0)
  let calls = Ref(0)
  client_material_result_plan(
    value,
    0,
    graph.result_plans,
    100000,
    10000,
    100,
    (owner, result, bytes, nodes, depth) => {
      calls.val += 1
      issue_prepared_client_result_plan(owner, result, bytes, nodes, depth)
    },
  ).unwrap()
  |> ignore
  assert_eq(calls.val, 0)
}
