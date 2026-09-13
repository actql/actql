///|
test "rename swaps simultaneously and drop/select consume checked projections" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"a\":\"a + 10\"}]}," +
      "{\"rename\":{\"a\":\"b\",\"b\":\"a\"}}," +
      "{\"filter\":\"b > 10\"},{\"drop\":[\"a\",\"a\"]},{\"select\":[\"b\"]}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [
      ordered_sequence_fragment_context(sequence, 100000L),
      sequence_fragment_context(sequence, 3, 2L),
    ],
    ["select_2", "select_5"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    execute_generated_sequence(generated, [], { ..limits, max_work: 0, })
    is Err(_),
  )
  for _i = 0; _i < 2; _i = _i + 1 {
    let completed = execute_generated_sequence(generated, [], limits).unwrap()
    let renamed = test_row_output(completed_output(completed, Step(2)).unwrap())
    assert_eq(renamed.names, ["b", "a"])
    assert_true(renamed.rows[0][0] is Number(11.0))
    assert_true(renamed.rows[0][1] is Number(0.0))
    let output = test_row_output(completed_output(completed, Step(5)).unwrap())
    assert_eq(output.names, ["b"])
    assert_eq(output.rows.length(), 1)
    assert_true(output.rows[0][0] is Number(11.0))
  }
}

///|
test "empty projection operations preserve empty schemas and their authored nodes" {
  for count in [0, 2] {
    let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
    let checked = @pipeline.check(
      input_cursor("[{\"rename\":{}},{\"drop\":[]}]"),
      [("seed", schema)],
      None,
      Some(input_cursor("\"seed\"")),
      {
        max_steps: 100,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap()
    let owner = @lower.bind_parameters(
      @lower.prepare(checked, {
        max_nodes: 100,
        max_references: 100,
        max_work: 10000,
        max_identifier_bytes: 10000,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let sequence = prepared_sequence(owner)
    assert_eq(@lower.sequence_count(sequence), 2)
    let supplied = capture_input(
      owner,
      0,
      Array::makei(count, _ => input_cursor("{}")),
      max_rows=2,
      run_limits().input_values,
    ).unwrap()
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      ["input_0", "select_0", "select_1"],
      100000,
      10000,
    ).unwrap()
    let completed = execute_generated_sequence(generated, [supplied], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    for step in [0, 1] {
      let table = test_row_output(
        completed_output(completed, Step(step)).unwrap(),
      )
      assert_eq(table.names.length(), 0)
      assert_eq(table.rows.length(), count)
    }
  }
}

///|
test "rename branch retains its original input" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"rename\":{\"a\":\"x\"},\"as\":\"renamed\"}," +
      "{\"drop\":[\"b\"],\"from\":\"seed\"}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["select_1", "select_2"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  assert_eq(
    test_row_output(completed_output(completed, Step(1)).unwrap()).names,
    ["x", "b"],
  )
  assert_eq(
    test_row_output(completed_output(completed, Step(2)).unwrap()).names,
    ["a"],
  )
}
