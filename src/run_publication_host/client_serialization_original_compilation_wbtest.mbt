///|
fn same_request_serialization_compilation_fixture() -> (
  PreparedClientProgram,
  ClientSerializationPlanGraph,
) {
  let owner = serialization_preparation_test_program(projected=true)
  let component = issue_prepared_client_serialization_plan_graph(
    owner,
    0,
    1,
    serialization_plan_test_policy(),
    2,
    128,
    3,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  (owner, component)
}

///|
test "serialization compiler reads the issuer original arrays without reparsing Graph wire" {
  let (owner, component) = same_request_serialization_compilation_fixture()
  let (nodes, edges, roots) = client_serialization_graph_original_parts(
    component, owner, 100000, 10000, 100,
  ).unwrap()
  assert_true(physical_equal(nodes, component.graph_nodes))
  assert_true(physical_equal(edges, component.graph_edges))
  assert_true(physical_equal(roots, component.graph_roots))
  let (again, _, _) = client_serialization_graph_original_parts(
    component, owner, 100000, 10000, 100,
  ).unwrap()
  assert_true(physical_equal(nodes, again))
  let copy = { ..component, graph: { ..component.graph, }, }
  assert_true(
    client_serialization_graph_original_parts(copy, owner, 100000, 10000, 100)
    is None,
  )
  let foreign = serialization_preparation_test_program(empty=true)
  assert_true(
    client_serialization_graph_original_parts(
      component, foreign, 100000, 10000, 100,
    )
    is None,
  )
  for
    (bytes, nodes, depth) in [
      (component.graph_wire_bytes - 1, 10000, 100),
      (100000, component.graph_wire_nodes - 1, 100),
      (100000, 10000, component.graph_wire_depth - 1),
    ] {
    assert_true(
      client_serialization_graph_original_parts(
        component, owner, bytes, nodes, depth,
      )
      is None,
    )
  }
}

///|
test "serialization final writer observation keeps original Plan and typed failure work" {
  let (owner, component) = same_request_serialization_compilation_fixture()
  let manifests = run_materials_manifests()
  let original = issue_prepared_client_serialization_compilation(
    owner, component, manifests, 1000, 1000, 100000, 10000, 100,
  ).unwrap()
  let parsed = @source.parse_json_bytes_measured(
    @utf8.encode(original.plan.plan.wire),
    { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let expected = 2L * parsed.usage.nodes.to_int64() - 1L
  let observed = Ref(-1L)
  let actual = observe_prepared_client_serialization_plan_encoding(
    owner,
    component,
    manifests,
    1000,
    1000,
    100000,
    10000,
    100,
    nodes_out=observed,
  ).unwrap()
  assert_eq(actual.plan.plan.wire, original.plan.plan.wire)
  assert_eq(actual.plan.plan.cid, original.plan.plan.cid)
  assert_true(physical_equal(actual.serialization.unwrap(), component))
  assert_eq(observed.val, expected)
  assert_true(
    observe_prepared_client_serialization_plan_encoding(
      owner,
      component,
      manifests,
      1000,
      1000,
      @utf8.encode(original.plan.plan.wire).length() - 1,
      10000,
      100,
      nodes_out=observed,
    )
    is Err(Plan(Encoding)),
  )
  assert_eq(observed.val, expected)
}

///|
test "same serialization compiler construction bounds cover the original completed Plan" {
  let (owner, component) = same_request_serialization_compilation_fixture()
  let manifests = run_materials_manifests()
  let limits : ClientPureCompilationLimits = {
    max_facts: 1000,
    max_witnesses: 1000,
    max_wire_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let storage = prepared_client_serialization_measurement_storage(
    owner, component, limits,
  ).unwrap()
  assert_true(@execution.preparation_representation_cost(storage).unwrap() > 0L)
  let geometry = measure_prepared_client_serialization_compilation_construction(
    owner, component, manifests, limits,
  ).unwrap()
  assert_true(geometry.tasks)
  assert_true(geometry.fragments.is_empty())
  assert_true(geometry.projections.is_empty())
  assert_eq(geometry.results.length(), 1)
  assert_eq(
    geometry.graph,
    (
      component.graph_wire_bytes,
      component.graph_wire_nodes,
      component.graph_wire_depth,
    ),
  )
  let original = issue_prepared_client_serialization_compilation(
    owner,
    component,
    manifests,
    limits.max_facts,
    limits.max_witnesses,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).unwrap()
  let parsed = @source.parse_json_bytes_measured(
    @utf8.encode(original.plan.plan.wire),
    {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    },
  ).unwrap()
  assert_true(
    geometry.executable_plan.0 >= @utf8.encode(original.plan.plan.wire).length(),
  )
  assert_true(geometry.executable_plan.1 >= parsed.usage.nodes)
  assert_true(geometry.executable_plan.2 >= parsed.usage.depth)
}
