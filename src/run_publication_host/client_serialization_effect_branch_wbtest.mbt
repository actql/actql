///|
test "Content Effect Plan retains an original pre-generation branch and its captured input" {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:9882e5f1412beaf650b0fdaf55035b198b7b87e8e9e3c3a0f07730953b0a72ed",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // The destination branch is a real checked Step, not another Stage import.
  // The post-generation JOIN needs both that branch and the Content barrier.
  let document =
    #|{"version":"actql/0.1","id":"content-branch","stages":[{"id":"capture","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"save","inputs":{"rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"derive":{"filename":{"literal":"out.jsonl"}},"as":"destinations"},{"select":["id","amount"],"as":"payload"},{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"},{"from":"attachment","join":{"with":"destinations","kind":"inner","on":[{"left":"name","right":"filename"}],"max_output_rows":2,"select":{"name":"left.name","id":"right.id"}},"as":"joined"},{"select":["name"]},{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"save","result":"out"}}}}
  let effect = prepare_client_effect_computation(
    document,
    Json,
    client_composed_effect_test_environment(base),
    None,
    [],
    { ..limits, program: client_standard_program_preparation_limits(), },
  ).unwrap()
  let owner = client_effect_program_view(effect)
  assert_eq(@strategy.graph_captured_prefix(owner.graph), 1)
  assert_eq(@checked.unit_count(@strategy.graph_program(owner.graph)), 2)
  prepare_client_query_acquisition(owner, 0, 0).unwrap() |> ignore
  let component = issue_client_serialization_effect_component(
      owner,
      run_materials_limits().sequence,
      1000000,
      100000,
      100,
    )
    .unwrap()
    .unwrap()
  let branch_id = "task_1_before_serialize_reference_0"
  assert_true(component.graph.wire.contains(branch_id))
  assert_false(component.graph.wire.contains("REL.values"))
  let branch = component.external_ports.filter(port => port.1 == branch_id)
  assert_eq(branch.length(), 1)
  assert_eq((branch[0].0, branch[0].2), ("rows", "rows"))
  let plan = issue_prepared_client_effect_compilation(
    effect,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
  )
  let plan = match plan {
    Ok(value) => value
    Err(Graph(ContractMismatch)) => fail("Plan graph contract mismatch")
    Err(Graph(InvalidEdge)) => fail("Plan graph invalid edge")
    Err(Graph(_)) => fail("Plan graph failure")
    Err(Plan(_)) => fail("Executable Plan failure")
    Err(Compilation(_)) => fail("Task compilation failure")
    Err(Material(_)) => fail("Execution material failure")
    Err(Template(_)) => fail("Bound template failure")
    Err(UnsupportedProgram) => fail("Unsupported original Effect shape")
    Err(Serialization(_)) => fail("Content component failure")
    Err(EffectPlan(_)) => fail("Effect terminal plan failure")
    Err(Encoding) => fail("Effect compiler encoding failure")
    Err(_) => fail("Effect compilation failure")
  }
  let wire = client_task_executable_plan_wire(
    client_effect_compilation_plan(plan),
  )
  // The source producer must bind the branch as well as the serializer input.
  assert_true(
    wire.contains(
      "\"to\":{\"node_id\":\"" + branch_id + "\",\"port\":\"rows\"}",
    ),
  )
  let graph = parse_plan_identity_value(
    component.graph.wire,
    1000000,
    100000,
    100,
  ).unwrap()
  guard @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) else {
    fail("Missing Content branch edges")
  }
  let mut borrowed = 0
  for edge in @canonical.array_values(edges) {
    let from = @canonical.object_field(edge, "from").unwrap()
    let to = @canonical.object_field(edge, "to").unwrap()
    if @canonical.object_field(from, "node_id")
      is Some(@canonical.String(actual)) &&
      actual == branch_id {
      assert_true(
        @canonical.object_field(to, "node_id")
        is Some(@canonical.String("task_1_after_serialize_4")),
      )
      assert_true(
        @canonical.object_field(to, "port")
        is Some(@canonical.String("input_1")),
      )
      borrowed += 1
    }
  }
  assert_eq(borrowed, 1)
}
