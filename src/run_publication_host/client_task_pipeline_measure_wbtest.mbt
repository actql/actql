///|
fn task_pipeline_geometry_original() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"task-input-long-path","stages":[{"id":"main","inputs":{},"steps":[{"as":"left","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"},{"id":2,"label":"second"}]}},{"from":"left","append":{"with":"left"},"as":"both"},{"from":"both","select":["label","id"],"as":"p0"},{"from":"p0","select":["label","id"],"as":"p1"},{"from":"p1","select":["label","id"],"as":"p2"},{"from":"p2","select":["label","id"],"as":"p3"},{"from":"p3","select":["label","id"],"as":"p4"},{"from":"p4","select":["label","id"],"as":"p5"},{"from":"p5","select":["label","id"],"as":"p6"},{"from":"p6","select":["label","id"],"as":"p7"},{"from":"p7","select":["label","id"],"as":"p8"},{"from":"p8","select":["label","id"],"as":"p9"},{"from":"p9","select":["label","id"],"as":"p10"},{"from":"p10","select":["label","id"],"as":"p11"}],"results":{"before":{"from":"left","fields":["id","label"]},"rows":{"from":"p11","fields":["label","id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}},"other":{"from":{"stage":"main","result":"before"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "Task input geometry uses the original writer and exact three-dimensional bounds" {
  let value = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let expected =
    #|{"output":"values_0","sources":{},"steps":[{"id":"values_0","in":[],"op":"REL.values","params":{"rows":[{"id":1},{"id":2}],"schema":{"id":{"nullable":false,"type":"number"}}}}],"version":"aoa-pipeline/0.1"}
  let (bytes, nodes, depth) = measure_prepared_client_task_pipeline_input(
    value, 0, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(bytes, expected.length())
  assert_eq(nodes, 19)
  assert_eq(depth, 6)
  let original = value.task_pipeline_inputs[0].input
  assert_eq(
    emit_prepared_client_task_pipeline(value, 0, limits, bytes, nodes, depth).unwrap(),
    expected,
  )
  assert_true(physical_equal(original, value.task_pipeline_inputs[0].input))
  assert_true(
    physical_equal(original.sequence, value.full_sequences[0].sequence),
  )
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      measure_prepared_client_task_pipeline_input(value, 0, limits, b, n, d)
      is Err(Encoding),
    )
    assert_true(
      emit_prepared_client_task_pipeline(value, 0, limits, b, n, d)
      is Err(Encoding),
    )
    assert_true(physical_equal(original, value.task_pipeline_inputs[0].input))
  }
}

///|
test "Task input geometry keeps long selected prefixes repeated inputs and both Results" {
  let value = task_pipeline_geometry_original()
  let graph = value.graph
  // Use the actual Program-selected profile, not the two-row test helper's
  // ten-binding envelope. No product capacity or codec guard is changed.
  let limits = prepared_client_values_sequence_limits(value)
  assert_eq(prepared_client_result_count(value), 2)
  assert_true(@strategy.graph_task_count(graph) > 1)
  let mut selected = 0
  let mut repeated = 0
  let mut raw_larger_than_output = false
  for task in 0..<@strategy.graph_task_count(graph) {
    let measured = match
      measure_prepared_client_task_pipeline_input(
        value, task, limits, 1000000, 100000, 100,
      ) {
      Ok(measured) => measured
      Err(Encoding) => fail("Task input Encoding at " + task.to_string())
      Err(MissingTask) => fail("Task input MissingTask at " + task.to_string())
      Err(MissingOutput) =>
        fail("Task input MissingOutput at " + task.to_string())
      Err(UnsupportedCarrier) =>
        fail("Task input UnsupportedCarrier at " + task.to_string())
      Err(Sequence(issue)) =>
        match issue {
          @lower.SequenceLimit =>
            fail("Task sequence limit at " + task.to_string())
          @lower.InvalidSequenceLimits =>
            fail("Task invalid limits at " + task.to_string())
          @lower.ValuesFailure(step, _) =>
            fail(
              "Task Values failure at " +
              task.to_string() +
              ":" +
              step.to_string(),
            )
          @lower.KernelFailure(step, _) =>
            fail(
              "Task Kernel failure at " +
              task.to_string() +
              ":" +
              step.to_string(),
            )
          @lower.AppendFailure(step, _) =>
            fail(
              "Task Append failure at " +
              task.to_string() +
              ":" +
              step.to_string(),
            )
          _ => fail("Task other sequence failure at " + task.to_string())
        }
    }
    let input = prepare_prepared_client_task_pipeline_input(value, task, limits).unwrap()
    let text = @encode.writer(1000000, 100000, 100)
    emit_client_task_pipeline_input_body(input, 1000000, 100000, 100, text)
    let raw = @encode.finish(text)
    assert_eq(measured.0, @utf8.encode(raw).length())
    let tree = parse_plan_identity_value(raw, 1000000, 100000, 100).unwrap()
    let out = @encode.measuring_writer(1000000, 100000, 100)
    @canonical.emit_value(tree, out)
    assert_eq(measured, @encode.finish_measurement_usage(out))
    let projected = emit_prepared_client_task_pipeline(
      value, task, limits, 1000000, 100000, 100,
    ).unwrap()
    assert_true(
      physical_equal(
        input,
        prepare_prepared_client_task_pipeline_input(value, task, limits).unwrap(),
      ),
    )
    if @strategy.graph_task_selected_step(graph, task) is Some(_) {
      selected += 1
      if measured.0 > @utf8.encode(projected).length() {
        raw_larger_than_output = true
      }
      if @strategy.graph_task_input_count(graph, task) == Some(2) {
        repeated += 1
        // Both declared input occurrences remain present. The existing first
        // matching producer reference rule is not a capacity aliasing rule.
        assert_true(projected.contains("\"input_0\":{\"sort\":\"relation\"}"))
        assert_true(projected.contains("\"input_1\":{\"sort\":\"relation\"}"))
      }
    }
  }
  assert_true(selected > 0)
  assert_eq(repeated, 1)
  assert_true(raw_larger_than_output)
  assert_eq(
    value.task_pipeline_inputs.length(),
    @strategy.graph_task_count(graph),
  )
}

///|
test "Task input retention replaces changed limits and refuses foreign original reuse" {
  let value = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let first = prepare_prepared_client_task_pipeline_input(value, 0, limits).unwrap()
  let changed = { ..limits, max_rows: limits.max_rows + 1, }
  let second = prepare_prepared_client_task_pipeline_input(value, 0, changed).unwrap()
  assert_false(physical_equal(first, second))
  assert_eq(value.task_pipeline_inputs.length(), 1)
  assert_true(
    prepare_prepared_client_task_pipeline_input(value, 0, {
      ..changed,
      max_rows: 1,
    })
    is Err(Sequence(_)),
  )
  assert_true(
    physical_equal(
      second,
      prepare_prepared_client_task_pipeline_input(value, 0, changed).unwrap(),
    ),
  )
  for task in [-1, 1] {
    assert_true(
      prepare_prepared_client_task_pipeline_input(value, task, limits)
      is Err(MissingTask),
    )
  }
  let foreign = values_compilation_parts_prepared()
  let other = prepare_prepared_client_task_pipeline_input(foreign, 0, limits).unwrap()
  assert_false(physical_equal(second.sequence, other.sequence))
  let view = with_prepared_client_values_row_limit(value, limits.max_rows).unwrap()
  assert_true(view.task_pipeline_inputs.is_empty())
  assert_false(
    physical_equal(
      second.sequence,
      prepare_prepared_client_task_pipeline_input(view, 0, limits).unwrap().sequence,
    ),
  )
}

///|
test "Task input measurement and construction retain ordered preparation once for exact codec bounds" {
  let value = ordered_client_program()
  let limits = run_materials_limits().sequence
  let input = prepare_prepared_client_task_pipeline_input(value, 0, limits).unwrap()
  let calls = Ref(0)
  let prepare = (sequence, first, end, bounds) => {
    calls.val += 1
    prepare_client_sequence_steps(sequence, first, end, bounds)
  }
  let original = client_task_pipeline_emission(
    input,
    1000000,
    100000,
    100,
    prepare~,
  )
  assert_eq(original.ordered.length(), 1)
  let measured = measure_prepared_client_task_pipeline_input(
    value, 0, limits, 1000000, 100000, 100,
  ).unwrap()
  let wire = emit_prepared_client_task_pipeline(
    value, 0, limits, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(measured.0, @utf8.encode(wire).length())
  let same = client_task_pipeline_emission(
    input,
    1000000,
    100000,
    100,
    prepare~,
  )
  assert_true(physical_equal(original, same))
  assert_eq(calls.val, 1)
  let changed = client_task_pipeline_emission(
    input,
    1000001,
    100000,
    100,
    prepare~,
  )
  assert_eq(calls.val, 2)
  assert_false(physical_equal(original, changed))
  assert_eq(changed.ordered.length(), 1)
  assert_true(
    try {
      client_task_pipeline_emission(input, 1, 100000, 100, prepare~) |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    physical_equal(
      changed,
      client_task_pipeline_emission(input, 1000001, 100000, 100, prepare~),
    ),
  )
  assert_eq(calls.val, 3)
}

///|
test "Task selected output preserves the initial writer guard before its smaller projection" {
  let value = task_pipeline_geometry_original()
  let limits = prepared_client_values_sequence_limits(value)
  let task = @strategy.graph_task_count(value.graph) - 1
  assert_true(@strategy.graph_task_selected_step(value.graph, task) is Some(_))
  let (bytes, nodes, depth) = measure_prepared_client_task_pipeline_input(
    value, task, limits, 1000000, 100000, 100,
  ).unwrap()
  let projected = emit_prepared_client_task_pipeline(
    value, task, limits, bytes, nodes, depth,
  ).unwrap()
  assert_true(@utf8.encode(projected).length() < bytes)
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      measure_prepared_client_task_pipeline_input(value, task, limits, b, n, d)
      is Err(Encoding),
    )
    assert_true(
      emit_prepared_client_task_pipeline(value, task, limits, b, n, d)
      is Err(Encoding),
    )
  }
}
