///|
fn sequence_test_kernel(
  overlap : String,
  contiguity : String,
  limits? : String = "",
) -> (@lower.BoundPrepared, @lower.PreparedSequenceMatch) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"clock\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"clock\":1,\"key\":1,\"value\":1}]},\"as\":\"events\"},{\"sequence\":{\"by\":[\"key\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"start\",\"where\":\"value = 1\"},{\"as\":\"end\",\"where\":\"value = 2\"}],\"within\":10,\"overlap\":\"" +
    overlap +
    "\",\"contiguity\":\"" +
    contiguity +
    "\"" +
    limits +
    "}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 1)
    is Some(@lower.SequenceMatchStep(kernel)) else {
    fail("sequence match kernel")
  }
  (owner, kernel)
}

///|
fn sequence_test_input(
  owner : @lower.BoundPrepared,
  kernel : @lower.PreparedSequenceMatch,
) -> Table {
  {
    owner,
    id: @lower.sequence_match_input(kernel),
    names: ["id", "clock", "key", "value"],
    rows: [
      [Number(3), Number(3), Number(1), Number(2)],
      [Number(1), Number(1), Number(1), Number(1)],
      [Number(4), Number(4), Number(2), Number(2)],
      [Number(2), Number(2), Number(1), Number(2)],
      [Number(5), Number(3), Number(2), Number(1)],
    ],
  }
}

///|
fn sequence_test_evaluate(
  overlap : String,
  contiguity : String,
  limits? : String = "",
) -> Result[Table, RowIssue] raise {
  let (owner, kernel) = sequence_test_kernel(overlap, contiguity, limits~)
  evaluate_sequence_match_rows(
    kernel,
    sequence_test_input(owner, kernel),
    100,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    { limit: 10000, live: 0, peak: 0, },
  )
}

///|
test "sequence match passes the common kernel budget sweep" {
  let (owner, kernel) = sequence_test_kernel("allow", "subsequence")
  let input = sequence_test_input(owner, kernel)
  assert_kernel_budget_sweep("sequence_match", (control, workspace) => {
    evaluate_sequence_match_rows(
      kernel,
      input,
      100,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
  })
}

///|
test "sequence allow returns every bounded match in canonical group order" {
  let table = sequence_test_evaluate("allow", "subsequence").unwrap()
  assert_eq(table.names, [
    "end_id", "end_time_ms", "key", "match_end_ms", "match_start_ms", "start_id",
    "start_time_ms",
  ])
  assert_true(
    join_numeric_rows_equal(table.rows, [
      [
        Number(2),
        Number(2),
        Number(1),
        Number(2),
        Number(1),
        Number(1),
        Number(1),
      ],
      [
        Number(3),
        Number(3),
        Number(1),
        Number(3),
        Number(1),
        Number(1),
        Number(1),
      ],
      [
        Number(4),
        Number(4),
        Number(2),
        Number(4),
        Number(3),
        Number(5),
        Number(3),
      ],
    ]),
  )
}

///|
test "sequence disallow consumes through the earliest complete match" {
  let table = sequence_test_evaluate("disallow", "adjacent").unwrap()
  assert_true(
    join_numeric_rows_equal(table.rows, [
      [
        Number(2),
        Number(2),
        Number(1),
        Number(2),
        Number(1),
        Number(1),
        Number(1),
      ],
      [
        Number(4),
        Number(4),
        Number(2),
        Number(4),
        Number(3),
        Number(5),
        Number(3),
      ],
    ]),
  )
}

///|
test "sequence enforces authored match guards atomically" {
  assert_true(
    sequence_test_evaluate(
      "allow",
      "subsequence",
      limits=",\"max_matches_per_key\":1,\"max_output_rows\":4",
    )
    is Err(RowLimit),
  )
  assert_true(
    sequence_test_evaluate(
      "allow",
      "subsequence",
      limits=",\"max_matches_per_key\":4,\"max_output_rows\":2",
    )
    is Err(RowLimit),
  )
}

///|
test "sequence executes through the generated managed driver" {
  let (owner, _) = sequence_test_kernel("allow", "subsequence")
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["sequence_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = test_row_output(
    completed_output(completed, @pipeline.Step(1)).unwrap(),
  )
  assert_eq(output.rows.length(), 0)
  assert_eq(output.names, [
    "end_id", "end_time_ms", "key", "match_end_ms", "match_start_ms", "start_id",
    "start_time_ms",
  ])
}

///|
test "sequence does not evaluate an undemanded later predicate" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"clock\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"clock\":1,\"key\":1,\"value\":1}]},\"as\":\"events\"},{\"sequence\":{\"by\":[\"key\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"start\",\"where\":\"value = 1\"},{\"as\":\"end\",\"where\":\"if(value = 99, 1 / 0 = 0, value = 2)\"}],\"within\":10,\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 1)
    is Some(@lower.SequenceMatchStep(kernel)) else {
    fail("sequence match kernel")
  }
  let input : Table = {
    owner,
    id: @lower.sequence_match_input(kernel),
    names: ["id", "clock", "key", "value"],
    rows: [
      [Number(9), Number(0), Number(1), Number(99)],
      [Number(1), Number(1), Number(1), Number(1)],
      [Number(2), Number(2), Number(1), Number(2)],
    ],
  }
  let result = evaluate_sequence_match_rows(
    kernel,
    input,
    10,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
    { limit: 10000, live: 0, peak: 0, },
  ).unwrap()
  assert_eq(result.rows.length(), 1)
}
