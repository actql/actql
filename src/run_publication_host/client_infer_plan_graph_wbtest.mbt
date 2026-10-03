///|
fn client_infer_graph_test_execution(
  prepared : PreparedClientProgram,
  occurrence? : ClientInferOccurrence? = None,
) -> @environment.ModelExecutionContract {
  let step = occurrence.map(value => value.step).unwrap_or(2)
  let owner = match occurrence {
    None => client_infer_prefix_owner(prepared, 0, 2).unwrap()
    Some(value) => value.preparation
  }
  guard @lower.payload(
      @lower.node_at(@lower.bound_preparation(owner), step).unwrap(),
    )
    is @lower.Infer(infer) else {
    abort("checked Infer fixture")
  }
  // Independent execution-contract vector from the contract reader tests.
  // Retry/backoff references here prove identity only, not executable policy.
  let wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  @environment.read_model_execution_contract(
    @infer.model_task(infer),
    @utf8.encode(wire),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
}

///|
test "Infer graph binds the exact prefix model contract and Result port" {
  let prepared = client_infer_prefix_test_program()
  assert_eq(
    prepared_client_infer_model_task_cid(prepared, 2),
    Some(
      "sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560",
    ),
  )
  assert_eq(prepared_client_infer_model_task_cid(prepared, 1), None)
  assert_eq(prepared_client_infer_model_task_cid(prepared, 3), None)
  let execution = client_infer_graph_test_execution(prepared)
  let issued = issue_prepared_client_infer_plan_graph(
    prepared,
    2,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(client_infer_plan_graph_matches(issued, prepared, execution))
  let item_limit = client_infer_plan_graph_item_limit(issued)
  assert_eq(@checked.infer_item_limit_maximum(item_limit), 1L)
  assert_true(
    @checked.infer_item_limit_matches(
      item_limit,
      @strategy.graph_program(prepared.graph),
      0,
      2,
    ),
  )
  assert_true(
    !client_infer_plan_graph_matches(
      issued,
      client_infer_prefix_test_program(),
      execution,
    ),
  )
  assert_eq(
    issued.request_wire,
    "{\"text\":{\"body\":\"text\",\"op\":\"field\"}}",
  )
  let graph = parse_plan_identity_value(issued.graph.wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(graph, "root_refs") is Some(@canonical.Array(roots)) else {
    abort("complete graph fixture")
  }
  let nodes = @canonical.array_values(nodes)
  let edges = @canonical.array_values(edges)
  let roots = @canonical.array_values(roots)
  assert_eq(nodes.length(), 2)
  assert_eq(edges.length(), 1)
  assert_eq(roots.length(), 1)
  assert_true(
    @canonical.object_field(nodes[0], "kind")
    is Some(@canonical.String("aoa_fragment")),
  )
  assert_true(
    @canonical.object_field(nodes[1], "kind")
    is Some(@canonical.String("acquisition_barrier")),
  )
  assert_true(
    @canonical.object_field(nodes[1], "node_id")
    is Some(@canonical.String("task_0_infer_2")),
  )
  assert_true(
    @canonical.object_field(nodes[1], "profile_id")
    is Some(@canonical.String("actql-infer/0.1")),
  )
  let barrier = @canonical.object_field(nodes[1], "barrier").unwrap()
  for
    (field, expected) in [
      ("input_fragment_cid", issued.input_fragment_cid),
      ("request_fragment_cid", issued.request_cid),
      ("barrier_cid", issued.barrier_cid),
      (
        "model_execution_contract_cid",
        @environment.model_execution_cid(execution),
      ),
      ("limits_cid", "sha256:" + "b".repeat(64)),
      ("egress_requirements_cid", "sha256:" + "c".repeat(64)),
      ("on_non_success", "outcomes"),
    ] {
    assert_true(
      @canonical.object_field(barrier, field) is Some(@canonical.String(actual)) &&
      actual == expected,
    )
  }
  assert_true(@canonical.object_field(barrier, "value") is None)
  let to = @canonical.object_field(edges[0], "to").unwrap()
  assert_true(
    @canonical.object_field(to, "node_id")
    is Some(@canonical.String("task_0_infer_2")),
  )
  let root_ref = @canonical.object_field(roots[0], "ref").unwrap()
  assert_true(
    @canonical.object_field(root_ref, "node_id")
    is Some(@canonical.String("task_0_infer_2")),
  )
  assert_eq(issued.graph.transformations.length(), 0)
}

///|
test "Infer projected Result and strict mode retain separate compilation identities" {
  let prepared = client_infer_prefix_test_program(
    result_fields="[\"id\",\"value\"]",
  )
  let strict = client_infer_prefix_test_program(
    result_fields="[\"id\",\"value\"]",
    strict=true,
  )
  let graph = prepared => {
    issue_prepared_client_infer_plan_graph(
      prepared,
      2,
      client_infer_graph_test_execution(prepared),
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    ).unwrap()
  }
  let projected = graph(prepared)
  let strict = graph(strict)
  assert_eq(projected.input_fragment_cid, strict.input_fragment_cid)
  assert_eq(projected.request_wire, strict.request_wire)
  assert_eq(projected.request_cid, strict.request_cid)
  assert_true(projected.barrier_cid != strict.barrier_cid)
  assert_eq(projected.graph.transformations.length(), 1)
  let value = parse_plan_identity_value(
    projected.graph.wire,
    100000,
    10000,
    100,
  ).unwrap()
  guard @canonical.object_field(value, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(value, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(value, "root_refs") is Some(@canonical.Array(roots)) else {
    abort("projected graph fixture")
  }
  let nodes = @canonical.array_values(nodes)
  let edges = @canonical.array_values(edges)
  let roots = @canonical.array_values(roots)
  assert_eq(nodes.length(), 3)
  assert_eq(edges.length(), 2)
  let from = @canonical.object_field(edges[1], "from").unwrap()
  assert_true(
    @canonical.object_field(from, "node_id")
    is Some(@canonical.String("task_0_infer_2")),
  )
  let root_ref = @canonical.object_field(roots[0], "ref").unwrap()
  assert_true(
    @canonical.object_field(root_ref, "node_id")
    is Some(@canonical.String("result_0")),
  )
}

///|
test "Infer graph rejects foreign contract owners invalid dependencies and short budgets" {
  let prepared = client_infer_prefix_test_program()
  let execution = client_infer_graph_test_execution(prepared)
  let limits = run_materials_limits().sequence
  assert_true(
    issue_prepared_client_infer_plan_graph(
      prepared,
      2,
      execution,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      limits,
      100000,
      10000,
      100,
      capacity_work=0,
    )
    is Err(ItemLimit(Preparation(@checked.UnitBuildFailure::BudgetExceeded))),
  )
  let issue = (step, contract, dependency, sequence) => {
    issue_prepared_client_infer_plan_graph(
      prepared,
      step,
      contract,
      dependency,
      "sha256:" + "c".repeat(64),
      sequence,
      100000,
      10000,
      100,
    )
  }
  let foreign = client_infer_graph_test_execution(
    client_infer_prefix_test_program(),
  )
  assert_true(
    issue(2, foreign, "sha256:" + "b".repeat(64), limits)
    is Err(ForeignExecution),
  )
  for dependency in ["", "sha256:" + "G".repeat(64), "sha256:" + "b".repeat(63)] {
    assert_true(
      issue(2, execution, dependency, limits) is Err(InvalidDependency),
    )
  }
  for step in [0, 1, 3] {
    assert_true(
      issue(step, execution, "sha256:" + "b".repeat(64), limits)
      is Err(UnsupportedProgram),
    )
  }
  assert_true(
    issue(2, execution, "sha256:" + "b".repeat(64), { ..limits, max_steps: 1, })
    is Err(Input(Pipeline(Sequence(@lower.SequenceLimit)))),
  )
  assert_true(
    issue(2, execution, "sha256:" + "b".repeat(64), { ..limits, max_steps: 2, })
    is Ok(_),
  )
}
