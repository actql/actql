///|
test "selected join output ceiling does not narrow either input row limit" {
  let generated = join_test_sequence(
    "[{\"id\":1,\"v\":10},{\"id\":2,\"v\":20}]", "[{\"id\":1,\"v\":30},{\"id\":3,\"v\":40}]",
  )
  let constrained = constrain_generated_join_output(generated, 2, 1L).unwrap()
  assert_true(
    physical_equal(
      generated_sequence_owner(constrained),
      generated_sequence_owner(generated),
    ),
  )
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let result = execute_generated_sequence(constrained, [], limits).unwrap()
  let output = completed_output(result, Step(2)).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
  let zero = constrain_generated_join_output(constrained, 2, 0L).unwrap()
  let cannot_weaken = constrain_generated_join_output(zero, 2, 100L).unwrap()
  assert_true(
    execute_generated_sequence(cannot_weaken, [], limits)
    is Err(Rows(2, RowLimit)),
  )
  assert_true(
    constrain_generated_join_output(generated, 0, 1L) is Err(InputSet),
  )
  assert_true(
    constrain_generated_join_output(generated, -1, 1L) is Err(InputSet),
  )
  assert_true(
    constrain_generated_join_output(generated, 2, -1L) is Err(InvalidLimits),
  )
}

///|
test "selected join limit rejects intermediate fanout even before a one row aggregate" {
  let rows = "[{\"id\":1,\"v\":10},{\"id\":1,\"v\":20}]"
  let generated = join_test_sequence(
    rows,
    rows,
    tail=",{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}",
  )
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let rejected = constrain_generated_join_output(generated, 2, 3L).unwrap()
  assert_true(
    execute_generated_sequence(rejected, [], limits) is Err(Rows(2, RowLimit)),
  )
  let accepted = constrain_generated_join_output(generated, 2, 4L).unwrap()
  let output = completed_output(
    execute_generated_sequence(accepted, [], limits).unwrap(),
    Step(3),
  ).unwrap()
  assert_true(completed_cell(output, 0, 0) is Some(Number(4)))
}
