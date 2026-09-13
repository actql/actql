///|
test "generated composition owns its selection and contexts and reuses no counters" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]},{\"filter\":\"total > 1\"},{\"select\":[\"total\",\"a\"]}",
    ),
  )
  let contexts = [
    ordered_sequence_fragment_context(sequence, 84L),
    sequence_fragment_context(sequence, 2, 2L),
  ]
  let selected = ["select_3"]
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    selected,
    100000,
    10000,
  ).unwrap()
  contexts.clear()
  selected[0] = "missing"
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
    let output = test_row_output(completed_output(completed, Step(3)).unwrap())
    assert_eq(output.names, ["total", "a"])
    assert_eq(output.rows.length(), 1)
    assert_true(output.rows[0][0] is Number(3.0))
    assert_true(output.rows[0][1] is Number(2.0))
  }
}

///|
test "generated composition rejects incomplete and foreign fragments before execution" {
  let make = fn() {
    prepared_sequence(row_owner(",{\"derive\":{\"x\":\"a + 1\"}}"))
  }
  let sequence = make()
  let contracts = registered_relation_contracts()
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [],
      ["derive_1"],
      100000,
      10000,
    )
    is Err(MissingFragmentContext(1)),
  )
  let foreign = sequence_fragment_context(make(), 1, 2L)
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [foreign],
      ["derive_1"],
      100000,
      10000,
    )
    is Err(FragmentContext(1, KernelMismatch)),
  )
  let valid = sequence_fragment_context(sequence, 1, 2L)
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [valid],
      ["derive_1"],
      100000,
      0,
    )
    is Err(Wiring(Limit)),
  )
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [valid],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(output.rows.length(), 2)
}
