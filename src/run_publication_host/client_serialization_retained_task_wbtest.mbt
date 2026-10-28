///|
test "intermediate SERIALIZE Result owns an exact retained task without repeating acquisition" {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"retained-content","stages":[{"id":"capture","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"save","inputs":{"rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"select":["id"],"as":"payload"},{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id"],"order_by":[{"id":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"},{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"attachment":{"from":"attachment","fields":["name","content","media_type","size_bytes","row_count"]},"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"attachment":{"from":{"stage":"save","result":"attachment"}},"published":{"from":{"stage":"save","result":"out"}}}}
  let effect = prepare_client_effect_computation(
    document,
    Json,
    client_composed_effect_test_environment(base),
    None,
    [],
    { ..limits, program: client_standard_program_preparation_limits(), },
  ).unwrap()
  let owner = client_effect_program_view(effect)
  let graph = owner.graph
  // Each selected occurrence has one existing completion/holding owner. The
  // original remote capture remains one task and is not split or repeated.
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@strategy.graph_task_count(graph), 5)
  assert_eq(prepared_client_serialization_occurrences(owner), [(3, 2)])
  assert_eq(
    @strategy.graph_stage_target_task(graph, 1, @pipeline.Step(2)),
    Some(3),
  )
  assert_eq(
    @strategy.graph_stage_target_task(graph, 1, @pipeline.Step(3)),
    Some(4),
  )
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(2))
  assert_eq(@strategy.graph_task_input_count(graph, 3), Some(1))
  let mut inputs = 0
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    if @strategy.data_edge_consumer(edge) == 3 {
      assert_eq(@strategy.data_edge_producer(edge), 2)
      assert_eq(@strategy.data_edge_target(edge), @pipeline.Step(1))
      assert_eq(@strategy.data_edge_operation_input(edge), Some((2, 0)))
      inputs += 1
    }
  }
  assert_eq(inputs, 1)
  prepare_client_query_acquisition(owner, 0, 0).unwrap() |> ignore
  let plan = issue_prepared_client_effect_compilation(
    effect,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let wire = client_task_executable_plan_wire(
    client_effect_compilation_plan(plan),
  )
  assert_true(wire.contains("task_3_serialize_2"))
  assert_true(wire.contains("\"node_id\":\"task_4\""))
  assert_false(wire.contains("REL.serialize"))
}
