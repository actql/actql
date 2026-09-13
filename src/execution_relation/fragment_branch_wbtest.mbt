///|
test "checked fragments preserve branch input and retained output independently of later filters" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"c\":\"a + 10\"},\"as\":\"augmented\"},{\"filter\":\"c > 10\"},{\"from\":\"augmented\",\"select\":[\"c\",\"b\"]}",
    ),
  )
  let contexts = [
    sequence_fragment_context(sequence, 1, 2L),
    sequence_fragment_context(sequence, 2, 2L),
  ]
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["where_2", "select_3"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    fragments=Some(contexts),
  ).unwrap()
  let filtered = test_row_output(completed_output(result, Step(2)).unwrap())
  let projected = test_row_output(completed_output(result, Step(3)).unwrap())
  assert_eq(filtered.rows.length(), 1)
  assert_eq(projected.names, ["c", "b"])
  assert_eq(projected.rows.length(), 2)
  assert_true(projected.rows[0][0] is Number(11.0))
  assert_true(projected.rows[1][0] is Number(10.0))
  assert_true(projected.rows[1][1] is Number(1.0))
  assert_true(test_row_store(result).tables[0] is None)
  assert_true(test_row_store(result).tables[1] is None)
}

///|
test "checked fragment execution retains unused branch failures and fresh retry counters" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"unused\":\"1 / b\"}},{\"from\":\"seed\",\"select\":[\"a\"]}",
    ),
  )
  let context = sequence_fragment_context(sequence, 1, 2L)
  for _attempt in 0..<2 {
    let result = evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["select_2"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([context]),
    )
    assert_true(
      result
      is Err(Rows(1, Evaluation(0, 0, { kind: Scalar(ArithmeticFailure), .. }))),
    )
  }
}

///|
test "checked fragments enforce cumulative output accounting across all four operators" {
  let (prepared, declarations) = parameter_preparation()
  let sequence = prepared_sequence(bind_number(prepared, declarations, 3))
  let contexts = [
    sequence_fragment_context(sequence, 1, 1L),
    sequence_fragment_context(sequence, 2, 1L),
  ]
  // The map retains a 3-node row, filter retains it again, and select retains
  // another 3-node row. Independent expectation: nine cumulative output nodes,
  // even though intermediate tables are released and contexts are per kernel.
  let exact = {
    ..run_limits(),
    output_values: {
      max_nodes: 9,
      max_text_bytes: 9,
      max_depth: 2,
      max_work: 18,
    },
  }
  let contracts = registered_relation_contracts()
  let run = fn(limits) {
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["select_3"],
      limits,
      { remaining: 100000, max_frames: 100, },
      fragments=Some(contexts),
    )
  }
  assert_true(
    run({ ..exact, output_values: { ..exact.output_values, max_nodes: 8, }, })
    is Err(Rows(3, RowLimit)),
  )
  let output = test_row_output(
    completed_output(run(exact).unwrap(), Step(3)).unwrap(),
  )
  assert_eq(output.names, ["v", "id"])
  assert_eq(output.rows.length(), 1)
  assert_true(output.rows[0][0] is Number(6.0))
}
