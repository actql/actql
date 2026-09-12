///|
test "input import seam preserves the single driver budgets ownership and order" {
  let owner = take_key_owner("[{\"take\":3},{\"select\":[\"s\"]},{\"take\":1}]")
  let sequence = prepared_sequence(owner)
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":3,\"s\":\"three\"}"),
      input_cursor("{\"n\":1,\"s\":\"one\"}"),
      input_cursor("{\"n\":2,\"s\":\"two\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let contracts = registered_relation_contracts()
  for _i = 0; _i < 2; _i = _i + 1 {
    let direct_control = { remaining: 100000, max_frames: 100, }
    let direct = evaluate_sequence_components(
      contracts,
      sequence,
      [input],
      ["limit_2"],
      run_limits(),
      direct_control,
    ).unwrap()
    let split_control = { remaining: 100000, max_frames: 100, }
    let invocation = prepare_sequence_invocation(
      contracts,
      sequence,
      [input],
      ["limit_2"],
      run_limits(),
      split_control,
      produced=[],
      fragments=None,
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    assert_true(physical_equal(invocation.control, split_control))
    assert_eq(invocation.store.next, 0)
    assert_eq(invocation.input_rows, 3)
    assert_true(split_control.remaining < 100000)
    let split = run_sequence_invocation(invocation).unwrap()
    assert_eq(split_control.remaining, direct_control.remaining)
    assert_eq(split.store.workspace.peak, direct.store.workspace.peak)
    let a = completed_output(direct, Step(2)).unwrap()
    let b = completed_output(split, Step(2)).unwrap()
    assert_eq(completed_row_count(a), 1)
    assert_eq(completed_row_count(b), 1)
    assert_true(completed_cell(a, 0, 0) is Some(Text("one")))
    assert_true(completed_cell(b, 0, 0) is Some(Text("one")))
    assert_true(physical_equal(split.sequence, sequence))
  }
}

///|
test "input seam neither skips complete key validation nor evaluates values early" {
  let owner = take_key_owner("[{\"take\":1}]")
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"one\"}"),
      input_cursor("{\"n\":1,\"s\":\"duplicate\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    prepare_sequence_invocation(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [input],
      ["limit_0"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      produced=[],
      fragments=None,
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    )
    is Err(InputKey(0, _)),
  )
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"unused\":\"1 / b\"}},{\"from\":\"seed\",\"select\":[\"a\"]}",
    ),
  )
  let invocation = prepare_sequence_invocation(
    registered_relation_contracts(),
    sequence,
    [],
    ["select_2"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    produced=[],
    fragments=None,
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  // values remain in their authored operation position, not hoisted over errors.
  assert_eq(invocation.input_rows, 0)
  assert_true(
    run_sequence_invocation(invocation)
    is Err(Rows(1, Evaluation(0, 0, { kind: Scalar(_), .. }))),
  )
}
