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
