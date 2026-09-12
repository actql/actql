///|
test "whole-row distinct preserves first occurrence and feeds take in the same driver" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"k\":2},{\"k\":1},{\"k\":2},{\"k\":null},{\"k\":null}]},\"as\":\"seed\"},{\"rename\":{\"k\":\"x\"}},{\"distinct\":true},{\"take\":{\"count\":1,\"offset\":1}}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["distinct_2", "limit_3"],
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
    let complete = execute_generated_sequence(generated, [], limits).unwrap()
    let distinct = completed_output(complete, Step(2)).unwrap().table
    assert_eq(distinct.names, ["x"])
    assert_eq(distinct.rows.length(), 3)
    assert_true(distinct.rows[0][0] is Number(2.0))
    assert_true(distinct.rows[1][0] is Number(1.0))
    assert_true(distinct.rows[2][0] is Null)
    assert_true(
      completed_output(complete, Step(3)).unwrap().table.rows[0][0]
      is Number(1.0),
    )
  }
}

///|
test "distinct comparison readiness depends on selected schema not row count" {
  for rows in ["[]", "[{\"k\":1,\"payload\":[1]}]"] {
    for projected in [false, true] {
      let sequence = prepared_sequence(
        bound_pipeline(
          "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":" +
          rows +
          "},\"as\":\"seed\"}" +
          (if projected { ",{\"select\":[\"k\"]}" } else { "" }) +
          ",{\"distinct\":true}]",
        ),
      )
      let step = if projected { 2 } else { 1 }
      let result = prepare_generated_sequence(
        registered_relation_contracts(),
        sequence,
        [],
        ["distinct_" + step.to_string()],
        100000,
        10000,
      )
      if projected {
        let complete = execute_generated_sequence(result.unwrap(), [], {
          rows: run_limits(),
          max_work: 100000,
          max_frames: 100,
        }).unwrap()
        assert_eq(completed_output(complete, Step(step)).unwrap().table.names, [
          "k",
        ])
      } else {
        assert_true(result is Err(UnsupportedRowComparison(1, _)))
      }
    }
  }
}

///|
test "empty-schema distinct collapses identical empty tuples but preserves empty input" {
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let checked = @pipeline.check(
    input_cursor("[{\"distinct\":true}]"),
    [("seed", schema)],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
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
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["distinct_0"],
    100000,
    10000,
  ).unwrap()
  for count in [0, 3] {
    let input = capture_input(
      owner,
      0,
      Array::makei(count, _ => input_cursor("{}")),
      max_rows=3,
      run_limits().input_values,
    ).unwrap()
    let complete = execute_generated_sequence(generated, [input], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    let table = completed_output(complete, Step(0)).unwrap().table
    assert_eq(table.names, [])
    assert_eq(table.rows.length(), if count == 0 { 0 } else { 1 })
  }
}
