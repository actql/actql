///|
fn cross_join_generated(
  left : String,
  right : String,
  options? : String = "",
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
    left +
    "},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":" +
    right +
    "},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"cross_join\":{\"with\":\"right_rows\",\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}" +
    options +
    "},\"as\":\"out\"}]",
  )
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["cross_join_2"],
    100000,
    10000,
  ).unwrap()
}

///|
test "cross join emits the left-major product and empty-side results" {
  let generated = cross_join_generated(
    "[{\"id\":1},{\"id\":2}]", "[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]",
  )
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(2)).unwrap())
  assert_eq(table.names, ["id", "tag"])
  assert_eq(table.rows.length(), 4)
  for
    (index, id, tag) in [
      (0, 1.0, "a"),
      (1, 1.0, "b"),
      (2, 2.0, "a"),
      (3, 2.0, "b"),
    ] {
    assert_true(table.rows[index][0] is Number(value) && value == id)
    assert_true(table.rows[index][1] is Text(value) && value == tag)
  }
  for
    (left, right) in [
      ("[]", "[{\"tag\":{\"literal\":\"a\"}}]"),
      ("[{\"id\":1}]", "[]"),
    ] {
    let result = execute_generated_sequence(
      cross_join_generated(left, right),
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
    ).unwrap()
    assert_eq(
      test_row_output(completed_output(result, Step(2)).unwrap()).rows.length(),
      0,
    )
  }
}

///|
test "cross join validates singleton and output ceilings atomically" {
  let singleton = cross_join_generated(
    "[{\"id\":1}]",
    "[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]",
    options=",\"right_rows\":\"one\"",
  )
  assert_true(
    execute_generated_sequence(singleton, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, InvalidRows)),
  )
  let limited = cross_join_generated(
    "[{\"id\":1},{\"id\":2}]",
    "[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]",
    options=",\"max_output_rows\":3",
  )
  assert_true(
    execute_generated_sequence(limited, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, RowLimit)),
  )
}

///|
test "cross join releases unpublished workspace after a bounded failure" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"cross_join\":{\"with\":\"right_rows\",\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}},\"as\":\"out\"}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.CrossJoinStep(kernel)) else {
    abort("cross join step")
  }
  let left = table_from_capture(
    capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap(),
  )
  let right = table_from_capture(
    capture_values(owner, 1, max_rows=2, run_limits().input_values).unwrap(),
  )
  let workspace = { limit: 8, live: 0, peak: 0, }
  let output = value_budget(run_limits().output_values).unwrap()
  assert_true(
    evaluate_cross_join_rows(
      kernel,
      left,
      right,
      4,
      { remaining: 10000, max_frames: 100, },
      output,
      workspace,
    )
    is Err(RowLimit),
  )
  assert_eq(workspace.live, 0)
  assert_true(workspace.peak > 0)
}
