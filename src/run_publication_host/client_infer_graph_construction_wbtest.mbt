///|
test "Model construction geometry covers original prefix request barrier and complete Result graph without issuer mutation" {
  let prepared = client_infer_prefix_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let before = prepared.task_pipeline_inputs.length()
  let geometry = measure_installed_client_composed_infer_graph_construction(
    occurrence,
    execution,
    client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(prepared.task_pipeline_inputs.length(), before)
  let issued = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  for
    (wire, upper) in [
      (issued.input.wire, geometry.fragments[0].fragment),
      (issued.request_wire, geometry.request),
      (issued.output.wire, geometry.node),
      (issued.graph.wire, geometry.graph),
    ] {
    let actual = content_construction_geometry(wire)
    assert_true(
      actual.0 <= upper.0 && actual.1 <= upper.1 && actual.2 <= upper.2,
    )
  }
  let other = client_infer_prefix_test_program()
  let foreign = client_infer_graph_test_execution(other)
  assert_true(
    measure_installed_client_composed_infer_graph_construction(
      occurrence,
      foreign,
      client_standard_values_sequence_limits(),
      100000,
      10000,
      100,
    )
    is Err(ForeignExecution),
  )
  assert_true(client_infer_plan_graph_matches(issued, prepared, execution))
}

///|
test "Model Graph consumes the same constructed mappings and lowered Fragments without entering input preparation again" {
  let prepared = client_infer_prefix_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let limits = client_standard_values_sequence_limits()
  let construction = measure_installed_client_composed_infer_graph_construction(
    occurrence, execution, limits, 100000, 10000, 100,
  ).unwrap()
  let mappings = construction.mappings
  let input = construction.pipeline_inputs[0]
  let emission = input.emission.unwrap()
  let calls = Ref(0)
  let graph = issue_client_infer_plan_graph_for_occurrence(
    occurrence,
    execution,
    prepared_client_check_environment_cid(prepared),
    @environment.model_task_identity(
      @environment.model_execution_task(execution),
    ).2,
    limits,
    100000,
    10000,
    100,
    1000000,
    false,
    construction=Some(construction),
    prepare_mappings=(infer, parameters, selected) => {
      calls.val += 1
      @lower.prepare_infer_inputs(infer, parameters, selected)
    },
  ).unwrap()
  assert_eq(calls.val, 0)
  assert_true(physical_equal(construction.mappings, mappings))
  assert_true(physical_equal(input.emission.unwrap(), emission))
  let original = issue_installed_client_composed_infer_plan_graph(
    occurrence, execution, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(graph.graph.wire, original.graph.wire)
  assert_eq(graph.request_wire, original.request_wire)
  assert_eq(graph.input.wire, original.input.wire)
  assert_eq(graph.output.wire, original.output.wire)
  assert_true(
    issue_installed_client_composed_infer_plan_graph(
      occurrence,
      execution,
      { ..limits, expressions: { ..limits.expressions, max_work: 0, }, },
      100000,
      10000,
      100,
      construction=Some(construction),
    )
    is Err(UnsupportedProgram),
  )
  let other = client_infer_prefix_test_program()
  let foreign = prepared_client_composed_infer_occurrence(other).unwrap()
  assert_true(
    issue_installed_client_composed_infer_plan_graph(
      foreign,
      execution,
      limits,
      100000,
      10000,
      100,
      construction=Some(construction),
    )
    is Err(UnsupportedProgram),
  )
}

///|
test "Model Graph keeps its original post-Infer lowering through measured suffix issuance" {
  let (_, environment) = client_infer_prefix_test_environment()
  let document =
    #|{"version":"actql/0.1","id":"infer-original-suffix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"},{"select":["id","outcome","value"],"as":"selected"}],"results":{"captured":{"from":"selected","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"captured"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let limits = client_standard_values_sequence_limits()
  let construction = measure_installed_client_composed_infer_graph_construction(
    occurrence, execution, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(construction.pipeline_inputs.length(), 2)
  let suffix = construction.pipeline_inputs[1]
  let emission = suffix.emission.unwrap()
  let graph = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    limits,
    100000,
    10000,
    100,
    construction=Some(construction),
  ).unwrap()
  assert_true(physical_equal(suffix.emission.unwrap(), emission))
  let original = issue_installed_client_composed_infer_plan_graph(
    occurrence, execution, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(graph.graph.wire, original.graph.wire)
  assert_eq(graph.output.wire, original.output.wire)
  assert_eq(graph.result_producers, original.result_producers)
}

///|
fn client_request_serialized_infer_construction_fixture() -> (
  PreparedClientProgram,
  ClientInferOccurrence,
  @environment.ModelExecutionContract,
  ClientSerializationPlanGraph,
) {
  let (_, environment) = client_infer_prefix_test_environment()
  let document =
    #|{"version":"actql/0.1","id":"request-serialized-model-original","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"serialize":{"format":"jsonl","fields":["id","text"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":1,"max_bytes":128}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]},"as":"unique_attachment"},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"},{"select":["name","outcome","value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["name","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let policy = serialization_plan_test_policy()
  let component = issue_prepared_client_serialization_plan_component(
    prepared,
    0,
    2,
    policy,
    1,
    128,
    10000,
    client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  (prepared, occurrence, execution, component)
}

///|
test "serialized Model construction retains the original Content producer and its lowered consumers through Graph issuance" {
  let (prepared, occurrence, execution, component) = client_request_serialized_infer_construction_fixture()
  let limits = client_standard_values_sequence_limits()
  let construction = measure_installed_client_composed_infer_graph_construction(
    occurrence,
    execution,
    limits,
    100000,
    10000,
    100,
    serialization=Some(component),
  ).unwrap()
  assert_true(physical_equal(construction.serialization.unwrap(), component))
  let original_input = construction.pipeline_inputs[0]
  let original_emission = original_input.emission.unwrap()
  let mappings = construction.mappings
  let calls = Ref(0)
  let graph = issue_client_infer_plan_graph_for_occurrence(
    occurrence,
    execution,
    prepared_client_check_environment_cid(prepared),
    @environment.model_task_identity(
      @environment.model_execution_task(execution),
    ).2,
    limits,
    100000,
    10000,
    100,
    1000000,
    true,
    serialization=Some(component),
    construction=Some(construction),
    prepare_mappings=(infer, parameters, selected) => {
      calls.val += 1
      @lower.prepare_infer_inputs(infer, parameters, selected)
    },
  ).unwrap()
  assert_eq(calls.val, 0)
  assert_true(physical_equal(construction.mappings, mappings))
  assert_true(
    physical_equal(original_input.emission.unwrap(), original_emission),
  )
  assert_true(physical_equal(graph.serialization.unwrap(), component))
  let original = issue_prepared_client_serialized_infer_plan_graph(
    occurrence, component, execution, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(graph.graph.wire, original.graph.wire)
  assert_eq(graph.request_wire, original.request_wire)
  for
    (wire, upper) in [
      (graph.request_wire, construction.request),
      (
        graph.output.wire,
        construction.fragments[construction.fragments.length() - 1].fragment,
      ),
      (graph.graph.wire, construction.graph),
    ] {
    let actual = content_construction_geometry(wire)
    assert_true(
      actual.0 <= upper.0 && actual.1 <= upper.1 && actual.2 <= upper.2,
    )
  }
}

///|
test "serialized Model construction rejects a foreign Content owner or a substituted equal component before issuance" {
  let (_, occurrence, execution, component) = client_request_serialized_infer_construction_fixture()
  let (_, _, _, foreign) = client_request_serialized_infer_construction_fixture()
  let limits = client_standard_values_sequence_limits()
  assert_true(
    measure_installed_client_composed_infer_graph_construction(
      occurrence,
      execution,
      limits,
      100000,
      10000,
      100,
      serialization=Some(foreign),
    )
    is Err(UnsupportedProgram),
  )
  let construction = measure_installed_client_composed_infer_graph_construction(
    occurrence,
    execution,
    limits,
    100000,
    10000,
    100,
    serialization=Some(component),
  ).unwrap()
  assert_true(
    issue_prepared_client_serialized_infer_plan_graph(
      occurrence,
      foreign,
      execution,
      limits,
      100000,
      10000,
      100,
      construction=Some(construction),
    )
    is Err(UnsupportedProgram),
  )
  assert_true(
    issue_prepared_client_serialized_infer_plan_graph(
      occurrence,
      component,
      execution,
      { ..limits, expressions: { ..limits.expressions, max_work: 0, }, },
      100000,
      10000,
      100,
      construction=Some(construction),
    )
    is Err(UnsupportedProgram),
  )
}
