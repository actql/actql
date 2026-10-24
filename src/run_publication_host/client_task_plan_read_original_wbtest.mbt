///|
fn task_plan_read_original_fixture() -> (
  PreparedClientProgram,
  ClientTaskExecutablePlan,
  @publication.RunEvidenceValue,
  ClientTaskPlanGraph,
) {
  let owner = values_compilation_parts_prepared()
  let (plan, template, graph) = issue_prepared_client_task_plan_parts(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  (owner, plan, template, graph)
}

///|
test "task Plan continuation retains exact original graph and complete compiled wire" {
  let (owner, plan, template, graph) = task_plan_read_original_fixture()
  let actual = client_task_compilation_graph_original(
    owner,
    plan,
    graph,
    100000,
    10000,
    100,
    original=plan.plan.read_originals,
  ).unwrap()
  assert_true(physical_equal(actual, plan.plan.read_originals.unwrap().graph))
  let decoded = parse_plan_identity_value(graph.wire, 100000, 10000, 100).unwrap()
  assert_true(!physical_equal(actual, decoded))
  assert_eq(
    @canonical.stringify_value(actual, 100000, 10000, 100),
    @canonical.stringify_value(decoded, 100000, 10000, 100),
  )
  // Force only the old full-reader branch without replacing any public bytes.
  let fallback : ClientTaskExecutablePlan = {
    plan: { ..plan.plan, read_originals: None, },
  }
  let compiled = finish_client_task_compilation(
    owner, plan, template, graph, 100000, 10000, 100,
  ).unwrap()
  assert_true(plan.plan.read_originals is None)
  let former = finish_client_task_compilation(
    owner, fallback, template, graph, 100000, 10000, 100,
  ).unwrap()
  assert_eq(compiled.plan.plan.wire, former.plan.plan.wire)
  assert_eq(compiled.plan.plan.cid, former.plan.plan.cid)
  assert_eq(
    @publication.publication_contract_json(compiled.compiled_plan),
    @publication.publication_contract_json(former.compiled_plan),
  )
  assert_eq(
    @publication.publication_contract_identity(compiled.compiled_plan),
    @publication.publication_contract_identity(former.compiled_plan),
  )
}

///|
test "task original reader retains tighter bounds and changed input fallbacks" {
  let (owner, plan, _, graph) = task_plan_read_original_fixture()
  let fallback : ClientTaskExecutablePlan = {
    plan: { ..plan.plan, read_originals: None, },
  }
  for
    (bytes, nodes, depth) in [
      (100000, 10000, 100),
      (100001, 10001, 101),
      (99999, 9999, 99),
      (1, 10000, 100),
      (0, 10000, 100),
      (-1, 10000, 100),
      (100000, 1, 100),
      (100000, 0, 100),
      (100000, 10000, 1),
      (100000, 10000, 0),
    ] {
    let expected = parse_plan_identity_value(graph.wire, bytes, nodes, depth)
    let actual = client_task_compilation_graph_original(
      owner,
      plan,
      graph,
      bytes,
      nodes,
      depth,
      original=plan.plan.read_originals,
    )
    assert_eq(actual is Some(_), expected is Some(_))
    match
      (
        client_task_plan_target_selections_cid(
          plan,
          bytes,
          nodes,
          depth,
          original=plan.plan.read_originals,
        ),
        client_task_plan_target_selections_cid(fallback, bytes, nodes, depth),
      ) {
      (Ok(actual), Ok(expected)) => assert_eq(actual, expected)
      (Err(Encoding), Err(Encoding)) => ()
      _ => abort("Different full-reader refusal")
    }
  }
  let foreign = values_compilation_parts_prepared()
  let foreign_graph = client_task_compilation_graph_original(
    foreign,
    plan,
    graph,
    100000,
    10000,
    100,
    original=plan.plan.read_originals,
  ).unwrap()
  assert_true(
    !physical_equal(foreign_graph, plan.plan.read_originals.unwrap().graph),
  )
  let changed : ClientTaskPlanGraph = { ..graph, wire: "{}", }
  assert_eq(
    @canonical.stringify_value(
      client_task_compilation_graph_original(
        owner,
        plan,
        changed,
        100000,
        10000,
        100,
        original=plan.plan.read_originals,
      ).unwrap(),
      100000,
      10000,
      100,
    ),
    "{}",
  )
  let invalid : ClientTaskExecutablePlan = {
    plan: { ..plan.plan, wire: "{", },
  }
  assert_true(
    client_task_plan_target_selections_cid(
      invalid,
      100000,
      10000,
      100,
      original=plan.plan.read_originals,
    )
    is Err(Encoding),
  )
}

///|
test "task original reader returns extra trees before refused continuation" {
  let (owner, plan, template, graph) = task_plan_read_original_fixture()
  assert_true(plan.plan.read_originals is Some(_))
  assert_true(
    finish_client_task_compilation(owner, plan, template, graph, 1, 10000, 100)
    is Err(Encoding),
  )
  assert_true(plan.plan.read_originals is None)
}

///|
test "standalone and Values Plan projections do not retain task reader trees" {
  let owner = values_compilation_parts_prepared()
  let limits = run_materials_limits()
  let manifests = run_materials_manifests()
  let values = issue_prepared_client_values_executable_plan(
    owner,
    manifests,
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(values.read_originals is None)
  let tasks = issue_prepared_client_task_executable_plan(
    owner,
    manifests,
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(tasks.plan.read_originals is None)
  let parts = issue_prepared_client_values_executable_plan_parts(
    owner,
    manifests,
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(parts.plan.read_originals is None)
  let compiled = issue_prepared_client_values_compilation(
    owner,
    manifests,
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(compiled.plan.read_originals is None)
}
