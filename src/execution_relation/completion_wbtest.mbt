///|
test "completed output keeps successful owner bindings and exact target" {
  let owner = row_owner(",{\"derive\":{\"c\":\"a + 10\"}},{\"select\":[\"c\"]}")
  let sequence = prepared_sequence(owner)
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["values_0", "select_2"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  for target in [@pipeline.Step(0), @pipeline.Step(2)] {
    let output = completed_output(completion, target).unwrap()
    assert_true(physical_equal(output.completion.sequence, sequence))
    assert_true(physical_equal(output.table.owner, owner))
    assert_eq(output.target, target)
  }
  let selected = completed_output(completion, Step(2)).unwrap()
  assert_true(selected.table.rows[0][0] is Number(11.0))
  assert_true(completed_output(completion, Step(1)) is None)
  assert_true(completed_output(completion, Step(-1)) is None)
  assert_true(completed_output(completion, Step(3)) is None)
  assert_true(completed_output(completion, Input(0)) is None)
}

///|
test "a retained prefix does not become completed output after a later failure" {
  let owner = row_owner(",{\"derive\":{\"unused\":\"1 / b\"}}")
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["values_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    )
    is Err(Rows(1, _)),
  )
}
