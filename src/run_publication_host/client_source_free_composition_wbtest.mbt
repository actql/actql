///|
test "source-free Relation producer compiles through the original terminal Effect owner" {
  let (_, environment, limits) = client_composed_effect_base_fixture()
  let document =
    #|{"version":"actql/0.1","id":"source-free-composition","stages":[{"id":"producer","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}},{"id":"effect","inputs":{"rows":{"result":{"stage":"producer","result":"out"}}},"steps":[{"select":["value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"effect","result":"out"}}}}
  let owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  assert_eq(@strategy.graph_task_count(graph), 2)
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(
    physical_equal(client_effect_compilation_owner(compilation), owner),
  )
  assert_eq(compilation.compiled.result_names, ["published"])
}
