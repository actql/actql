///|
test "measurement collections come from original inventory without lowering or codec headroom" {
  let standard = client_standard_pure_compilation_limits()
  let roomy = {
    max_facts: 2000,
    max_witnesses: 20000,
    max_wire_bytes: 2000000,
    max_nodes: 200000,
    max_depth: 200,
  }
  let simple = values_compilation_parts_prepared()
  let long = task_pipeline_geometry_original()
  let mut previous_cost = 0L
  for value in [simple, long] {
    let sequences = value.full_sequences.length()
    let pipelines = value.task_pipeline_inputs.length()
    let units = match
      prepared_client_pure_measurement_storage(value, standard) {
      Ok(units) => units
      Err(_) =>
        abort(
          "storage unavailable: tasks=" +
          @strategy.graph_task_count(value.graph).to_string() +
          ",results=" +
          @strategy.graph_result_count(value.graph).to_string() +
          ",edges=" +
          @strategy.graph_data_count(value.graph).to_string() +
          ",units=" +
          @checked.unit_count(@strategy.graph_program(value.graph)).to_string(),
        )
    }
    assert_true(
      units == prepared_client_pure_measurement_storage(value, roomy).unwrap(),
    )
    assert_eq(value.full_sequences.length(), sequences)
    assert_eq(value.task_pipeline_inputs.length(), pipelines)
    assert_eq(units.owned_wire_bytes, 0L)
    assert_true(units.reference_slots > 0L && units.scalar_words > 0L)
    let cost = @execution.preparation_representation_cost(units).unwrap()
    assert_true(cost > previous_cost)
    previous_cost = cost
  }
}

///|
test "compiler measurement label lengths use the original decimal coordinate constructors" {
  for
    (index, task, result) in [
      (0, "task_0", "result_0"),
      (9, "task_9", "result_9"),
      (10, "task_10", "result_10"),
      (99, "task_99", "result_99"),
      (100, "task_100", "result_100"),
      (2147483646, "task_2147483646", "result_2147483646"),
    ] {
    assert_eq(client_compilation_task_node_id(index), task)
    assert_eq(client_compilation_result_node_id(index), result)
  }
}
