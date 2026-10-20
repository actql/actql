///|
fn captured_infer_result_fixture() -> (
  PreparedClientEffectComputation,
  ClientInferPlanGraph,
) raise {
  let (_, _, base_limits) = client_composed_effect_base_fixture()
  let (original, _, _, _) = composed_infer_run_materials_fixture()
  let checked = @strategy.graph_program(original.graph)
  let environment = @checked.checking_environment(
    @checked.checked_environment(checked),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=@checked.checked_model_tasks(checked),
  )
  let document =
    #|{"version":"actql/0.1","id":"captured-infer-result","stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"right","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"classify","inputs":{"left_rows":{"result":{"stage":"left","result":"rows"}},"right_rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","value":"right.amount"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]},"as":"joined"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"joined","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"value":"right.value"}}},{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"}}}}}],"results":{"published":{"from":{"stage":"classify","result":"rows"}}}}
  // Public Result and Effect input are different checked occurrences in the
  // same Unit. The Result precedes the later Effect-only projection.
  let document = document
    .replace(
      old="\"select\":{\"value\":\"right.value\"}}}",
      new="\"select\":{\"value\":\"right.value\"}},\"as\":\"reviewed\"}",
    )
    .replace(
      old="\"rows\":{\"from\":\"selected\",\"fields\":[\"value\"]}",
      new="\"rows\":{\"from\":\"reviewed\",\"fields\":[\"value\"]},\"write_rows\":{\"from\":\"selected\",\"fields\":[\"value\"]}",
    )
    .replace(
      old="\"from\":{\"result\":\"rows\"}",
      new="\"from\":{\"result\":\"write_rows\"}",
    )
  let owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    { ..base_limits, program: client_standard_program_preparation_limits(), },
  ).unwrap()
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (2, 2, 3))
  assert_eq(
    @strategy.graph_task_target(occurrence.owner.graph, 2),
    Some(@pipeline.Step(5)),
  )
  assert_eq(
    @results.port_target(
      @execution.managed_result_occurrence_port(
        @strategy.graph_result_occurrence(occurrence.owner.graph, 0).unwrap(),
      ),
    ),
    @pipeline.Step(4),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    client_infer_graph_test_execution(occurrence.owner, occurrence=Some(occurrence)),
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  (owner, component)
}

///|
test "captured JOIN INFER Result retains its original intermediate producer in an Effect compilation" {
  let (owner, component) = captured_infer_result_fixture()
  let compiled = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_eq(compiled.compiled.result_names, ["published"])
  assert_eq(compiled.compiled.plan.plan.transformations.length(), 1)
  let selected = compiled.compiled.plan.plan.transformations[0]
  assert_true(client_result_transformation_matches(selected, component.owner, 0))
  assert_true(physical_equal(compiled.compiled.infer.unwrap(), component))
  let foreign = captured_infer_result_fixture().0
  assert_true(
    issue_prepared_client_effect_compilation(
      foreign,
      run_materials_manifests(),
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
      infer=Some(component),
    )
    is Err(ForeignInferOwner),
  )
}

///|
test "captured INFER Result transformation refuses a foreign occurrence and wrong terminal or port" {
  let (_, component) = captured_infer_result_fixture()
  let occurrence = prepared_client_composed_infer_occurrence(component.owner).unwrap()
  let terminal = @lower.preparation_output_target(
    @lower.bound_preparation(occurrence.preparation),
  ).unwrap()
  guard terminal is @pipeline.Step(terminal) else { fail("checked terminal") }
  let (_, foreign) = captured_infer_result_fixture()
  let foreign_occurrence = prepared_client_composed_infer_occurrence(foreign.owner).unwrap()
  for (selected, step, port) in [
    (foreign_occurrence, terminal, component.output.output_port),
    (occurrence, terminal - 1, component.output.output_port),
    (occurrence, terminal, "foreign-output"),
  ] {
    assert_true(
      issue_client_result_plan_parts(
        component.owner,
        0,
        component.output.node_id,
        port,
        component.output.output_contract_cid,
        100000,
        10000,
        100,
        infer_output=Some((selected, step)),
      )
      is Err(Root(RequiresResultTransformation)),
    )
  }
}
