///|
test "Task Fragment consumes its original canonical pipeline with unchanged roundtrip identities" {
  let programs = [
    values_compilation_parts_prepared(),
    task_pipeline_geometry_original(),
    task_projection_ordered_original(),
  ]
  let mut selected = 0
  let mut repeated = 0
  for value in programs {
    let limits = prepared_client_values_sequence_limits(value)
    for task in 0..<@strategy.graph_task_count(value.graph) {
      let original = construct_prepared_client_task_pipeline(
        value, task, limits, 1000000, 100000, 100,
      ).unwrap()
      // Independent test-only old roundtrip. Product Fragment construction
      // consumes the original value; foreign and Saved wire still admit fully.
      let parsed = parse_plan_identity_value(
        original.wire,
        1000000,
        100000,
        100,
      ).unwrap()
      assert_eq(
        @canonical.stringify_value(original.body, 1000000, 100000, 100),
        original.wire,
      )
      assert_eq(
        @canonical.stringify_value(parsed, 1000000, 100000, 100),
        original.wire,
      )
      let owner = @strategy.graph_task_owner(value.graph, task).unwrap()
      let target = client_task_output_target(value.graph, task).unwrap()
      let step = @strategy.graph_task_selected_step(value.graph, task)
      let actual = issue_client_task_fragment_body(
        owner,
        target,
        step,
        "task_" + task.to_string(),
        original,
        1000000,
        100000,
        100,
      ).unwrap()
      let old_roundtrip = issue_client_task_fragment_body(
        owner,
        target,
        step,
        "task_" + task.to_string(),
        { wire: original.wire, body: parsed, },
        1000000,
        100000,
        100,
      ).unwrap()
      assert_eq(actual.wire, old_roundtrip.wire)
      assert_eq(actual.logical_cid, old_roundtrip.logical_cid)
      assert_eq(actual.output_contract_cid, old_roundtrip.output_contract_cid)
      assert_eq(
        issue_prepared_client_task_fragment(
          value, task, limits, 1000000, 100000, 100,
        ).unwrap().wire,
        actual.wire,
      )
      if step is Some(_) {
        selected += 1
      }
      if @strategy.graph_task_input_count(value.graph, task).unwrap_or(0) > 1 {
        repeated += 1
      }
    }
  }
  assert_true(selected > 0)
  assert_true(repeated > 0)
}

///|
test "original Task pipeline keeps its exact canonical codec boundaries and Saved admission" {
  let value = values_compilation_parts_prepared()
  let limits = run_materials_limits().sequence
  let expected =
    #|{"output":"values_0","sources":{},"steps":[{"id":"values_0","in":[],"op":"REL.values","params":{"rows":[{"id":1},{"id":2}],"schema":{"id":{"nullable":false,"type":"number"}}}}],"version":"aoa-pipeline/0.1"}
  let original = construct_prepared_client_task_pipeline(
    value,
    0,
    limits,
    expected.length(),
    19,
    6,
  ).unwrap()
  assert_eq(original.wire, expected)
  let retained = value.task_pipeline_inputs[0].input
  for
    (bytes, nodes, depth) in [
      (expected.length() - 1, 19, 6),
      (expected.length(), 18, 6),
      (expected.length(), 19, 5),
    ] {
    assert_true(
      construct_prepared_client_task_pipeline(
        value, 0, limits, bytes, nodes, depth,
      )
      is Err(Encoding),
    )
    assert_true(physical_equal(retained, value.task_pipeline_inputs[0].input))
  }
  let fragment = issue_prepared_client_task_fragment(
    value, 0, limits, 1000000, 100000, 100,
  ).unwrap()
  admit_prepared_client_task_fragment(
    value,
    0,
    fragment.wire,
    limits,
    1000000,
    100000,
    100,
  ).unwrap()
  |> ignore
  assert_true(
    admit_prepared_client_task_fragment(
      value, 0, "{}", limits, 1000000, 100000, 100,
    )
    is Err(MismatchedNode),
  )
  let foreign = task_pipeline_geometry_original()
  assert_true(
    admit_prepared_client_task_fragment(
      foreign,
      0,
      fragment.wire,
      prepared_client_values_sequence_limits(foreign),
      1000000,
      100000,
      100,
    )
    is Err(MismatchedNode),
  )
}
