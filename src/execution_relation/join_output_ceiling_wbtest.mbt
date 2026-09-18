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

///|
fn two_join_test_sequence() -> GeneratedSequence raise {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"v\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"id\":1,\"v\":10}]},\"as\":\"l\"}," +
    "{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"id\":1,\"v\":20},{\"id\":1,\"v\":21}]},\"as\":\"r\"}," +
    "{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"l\":\"left.v\",\"r\":\"right.v\"}},\"as\":\"first\"}," +
    "{\"from\":\"first\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"l\":\"left.l\",\"r1\":\"left.r\",\"r2\":\"right.v\"}}}]",
  )
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["join_3"],
    100000,
    10000,
  ).unwrap()
}

///|
test "selected join ceilings bind every invocation independently" {
  let generated = two_join_test_sequence()
  let constrained = constrain_generated_join_output(
    constrain_generated_join_output(generated, 2, 2L).unwrap(),
    3,
    4L,
  ).unwrap()
  let requirements = generated_sequence_requirements(constrained, 100).unwrap()
  assert_eq(@lower.sequence_requirements_join_count(requirements), 2)
  assert_eq(
    @lower.sequence_requirements_join_at(requirements, 0),
    Some((2, 2L)),
  )
  assert_eq(
    @lower.sequence_requirements_join_at(requirements, 1),
    Some((3, 4L)),
  )
  assert_true(generated_satisfies_requirements(constrained, requirements))
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let result = execute_generated_sequence(constrained, [], limits).unwrap()
  assert_eq(completed_row_count(completed_output(result, Step(3)).unwrap()), 4)
  let first_rejected = constrain_generated_join_output(
    constrain_generated_join_output(generated, 2, 1L).unwrap(),
    3,
    4L,
  ).unwrap()
  assert_true(
    execute_generated_sequence(first_rejected, [], limits)
    is Err(Rows(2, RowLimit)),
  )
  let second_rejected = constrain_generated_join_output(
    constrain_generated_join_output(generated, 2, 2L).unwrap(),
    3,
    3L,
  ).unwrap()
  assert_true(
    execute_generated_sequence(second_rejected, [], limits)
    is Err(Rows(3, RowLimit)),
  )
}
