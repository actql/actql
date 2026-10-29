///|
fn task_projection_ordered_original() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"projection-measure-ordered","stages":[{"id":"main","inputs":{},"steps":[{"as":"left","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]}},{"as":"right","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]}},{"from":"left","append":{"with":"right"},"as":"both"},{"from":"both","derive":[{"x0":{"add":[{"field":"id"},{"literal":0}]}},{"x1":{"add":[{"field":"id"},{"literal":1}]}},{"x2":{"add":[{"field":"id"},{"literal":2}]}},{"x3":{"add":[{"field":"id"},{"literal":3}]}},{"x4":{"add":[{"field":"id"},{"literal":4}]}},{"x5":{"add":[{"field":"id"},{"literal":5}]}},{"x6":{"add":[{"field":"id"},{"literal":6}]}},{"x7":{"add":[{"field":"id"},{"literal":7}]}},{"x8":{"add":[{"field":"id"},{"literal":8}]}},{"x9":{"add":[{"field":"id"},{"literal":9}]}},{"x10":{"add":[{"field":"id"},{"literal":10}]}},{"x11":{"add":[{"field":"id"},{"literal":11}]}},{"x12":{"add":[{"field":"id"},{"literal":12}]}},{"x13":{"add":[{"field":"id"},{"literal":13}]}},{"x14":{"add":[{"field":"id"},{"literal":14}]}},{"x15":{"add":[{"field":"id"},{"literal":15}]}}],"as":"derived"}],"results":{"before":{"from":"left","fields":["id"]},"rows":{"from":"derived","fields":["id","x15"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}},"other":{"from":{"stage":"main","result":"before"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "Task projection geometry covers exact selected structure and input occurrences" {
  let value = task_pipeline_geometry_original()
  let limits = prepared_client_values_sequence_limits(value)
  let mut selected = 0
  for task in 0..<@strategy.graph_task_count(value.graph) {
    let (initial, upper) = measure_prepared_client_task_pipeline_construction(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    assert_eq(
      initial,
      measure_prepared_client_task_pipeline_input(
        value, task, limits, 1000000, 100000, 100,
      ).unwrap(),
    )
    let wire = emit_prepared_client_task_pipeline(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    let tree = parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap()
    let writer = @encode.measuring_writer(1000000, 100000, 100)
    @canonical.emit_value(tree, writer)
    let actual = @encode.finish_measurement_usage(writer)
    assert_true(actual.0 <= upper.0)
    assert_eq(actual.1, upper.1)
    assert_eq(actual.2, upper.2)
    if @strategy.graph_task_selected_step(value.graph, task) is Some(_) {
      selected += 1
    }
  }
  assert_true(selected > 0)
  assert_eq(prepared_client_result_count(value), 2)
}

///|
test "Task projection byte bound uses actual successful writer headroom without a cap change" {
  let value = task_projection_ordered_original()
  let limits = prepared_client_values_sequence_limits(value)
  let mut clamped = 0
  for task in 0..<@strategy.graph_task_count(value.graph) {
    let initial = measure_prepared_client_task_pipeline_input(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    let (_, upper) = measure_prepared_client_task_pipeline_construction(
      value,
      task,
      limits,
      initial.0,
      100000,
      100,
    ).unwrap()
    let wire = emit_prepared_client_task_pipeline(
      value,
      task,
      limits,
      initial.0,
      100000,
      100,
    ).unwrap()
    assert_true(@utf8.encode(wire).length() <= upper.0)
    assert_true(upper.0 <= initial.0)
    if @strategy.graph_task_selected_step(value.graph, task) is Some(_) &&
      upper.0 == initial.0 {
      clamped += 1
    }
  }
  assert_true(clamped > 0)
}

///|
test "Task projection measurement preserves initial refusal and full scalar text" {
  let value = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let (initial, output) = measure_prepared_client_task_pipeline_construction(
    value, 0, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(initial, output)
  for
    (b, n, d) in [
      (initial.0 - 1, initial.1, initial.2),
      (initial.0, initial.1 - 1, initial.2),
      (initial.0, initial.1, initial.2 - 1),
      (0, 10000, 100),
    ] {
    assert_true(
      measure_prepared_client_task_pipeline_construction(
        value, 0, limits, b, n, d,
      )
      is Err(Encoding),
    )
  }
  for task in [-1, 1] {
    assert_true(
      measure_prepared_client_task_pipeline_construction(
        value, task, limits, 100000, 10000, 100,
      )
      is Err(MissingTask),
    )
  }
  let foreign = values_compilation_parts_prepared()
  measure_prepared_client_task_pipeline_construction(
    foreign, 0, limits, 100000, 10000, 100,
  ).unwrap()
  |> ignore
  assert_false(
    physical_equal(
      value.task_pipeline_inputs[0].input,
      foreign.task_pipeline_inputs[0].input,
    ),
  )
}

///|
test "Task projected range consumes the same prepared ordered params and rejects foreign bounds" {
  let value = ordered_client_program()
  let input = prepare_prepared_client_task_pipeline_input(
    value,
    0,
    run_materials_limits().sequence,
  ).unwrap()
  let original = client_task_pipeline_emission(input, 1000000, 100000, 100)
  assert_eq(original.ordered.length(), 1)
  let params = original.ordered[0].1
  let range = @encode.writer(1000000, 100000, 100)
  emit_prepared_client_sequence_range(original, 1, 2, range)
  let wire = @encode.finish(range)
  let independent = @encode.writer(1000000, 100000, 100)
  @encode.begin_array(independent)
  @execution.emit_ordered_kernel_node(params, independent)
  @encode.end_array(independent)
  assert_eq(wire, @encode.finish(independent))
  assert_true(physical_equal(params, original.ordered[0].1))
  for (first, end) in [(-1, 2), (1, 4), (2, 1)] {
    let writer = @encode.measuring_writer(1000000, 100000, 100)
    assert_true(
      try {
        emit_prepared_client_sequence_range(original, first, end, writer)
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    physical_equal(
      original,
      client_task_pipeline_emission(input, 1000000, 100000, 100),
    ),
  )
}

///|
test "Task Fragment construction geometry includes the exact full pipeline and CID fields" {
  let value = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let measured = measure_prepared_client_task_fragment_construction(
    value, 0, limits, 100000, 10000, 100,
  ).unwrap()
  let initial = measured.initial_pipeline
  let pipeline = measured.pipeline
  let fragment = measured.fragment
  assert_eq(initial, pipeline)
  assert_eq(fragment.1, 26)
  assert_eq(fragment.2, 7)
  let issued = issue_prepared_client_task_fragment(
    value, 0, limits, 100000, 10000, 100,
  ).unwrap()
  let tree = parse_plan_identity_value(issued.wire, 100000, 10000, 100).unwrap()
  let writer = @encode.measuring_writer(100000, 10000, 100)
  @canonical.emit_value(tree, writer)
  assert_eq(fragment, @encode.finish_measurement_usage(writer))
  for (b, n, d) in [(100000, 0, 100), (0, 10000, 100), (100000, 10000, 0)] {
    assert_true(
      measure_prepared_client_task_fragment_construction(
        value, 0, limits, b, n, d,
      )
      is Err(InvalidLimits),
    )
  }
}

///|
test "Task Fragment upper geometry retains every selected port and ordered payload" {
  let value = task_projection_ordered_original()
  let limits = prepared_client_values_sequence_limits(value)
  for task in 0..<@strategy.graph_task_count(value.graph) {
    let measured = measure_prepared_client_task_fragment_construction(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    let issued = issue_prepared_client_task_fragment(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    let pipeline = measured.pipeline
    let fragment = measured.fragment
    assert_true(pipeline.0 < fragment.0)
    let tree = parse_plan_identity_value(issued.wire, 1000000, 100000, 100).unwrap()
    let writer = @encode.measuring_writer(1000000, 100000, 100)
    @canonical.emit_value(tree, writer)
    let actual = @encode.finish_measurement_usage(writer)
    assert_true(actual.0 <= fragment.0)
    assert_eq(actual.1, fragment.1)
    assert_eq(actual.2, fragment.2)
  }
}

///|
test "Task Fragment Unicode and repeated-input geometry uses complete original payloads" {
  let value = task_pipeline_geometry_original()
  let limits = prepared_client_values_sequence_limits(value)
  for task in 0..<@strategy.graph_task_count(value.graph) {
    let measured = measure_prepared_client_task_fragment_construction(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    let issued = issue_prepared_client_task_fragment(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    let parsed = parse_plan_identity_value(issued.wire, 1000000, 100000, 100).unwrap()
    let writer = @encode.measuring_writer(1000000, 100000, 100)
    @canonical.emit_value(parsed, writer)
    let actual = @encode.finish_measurement_usage(writer)
    let upper = measured.fragment
    assert_true(actual.0 <= upper.0)
    assert_eq(actual.1, upper.1)
    assert_eq(actual.2, upper.2)
  }
}
