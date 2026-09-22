///|
fn assert_sort_text_cell(
  output : @execution.CompletedOutput,
  row : Int,
  column : Int,
  expected : String,
) -> Unit raise {
  assert_true(
    @execution.completed_cell(output, row, column) is Some(Text(actual)) &&
    actual == expected,
  )
}

///|
test "Local sort take preserves UTF-16 order null placement and stable ties" {
  let input = duckdb_fixed_values(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"string\",\"nullable\":true},\"tag\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":\"a\",\"tag\":0},{\"k\":null,\"tag\":1},{\"k\":\"𐀀\",\"tag\":2},{\"k\":\"\",\"tag\":3},{\"k\":\"a\",\"tag\":4},{\"k\":\"퟿\",\"tag\":5}]},\"as\":\"seed\"}]",
    steps="[{\"sort\":[{\"field\":\"k\",\"dir\":\"desc\",\"nulls\":\"first\"}]},{\"take\":{\"count\":4,\"offset\":1}}]",
  )
  let owner = @execution.producer_read_receiver(input)
  let completed = @execution.execute_fixed_producers_guarded(
    compute_test_sequence(owner),
    [input],
    Step(1),
    compute_test_limits(),
    max_rows=100,
    max_value_bytes=1000,
    { max_nodes: 10000, max_bytes: 100000, max_depth: 100, max_work: 100000, },
  ).unwrap()
  let output = @execution.completed_output(completed, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 4)
  for
    (row, key, tag) in [
      (0, "", 3.0),
      (1, "𐀀", 2.0),
      (2, "퟿", 5.0),
      (3, "a", 0.0),
    ] {
    assert_sort_text_cell(output, row, 0, key)
    assert_true(
      @execution.completed_cell(output, row, 1) is Some(Number(actual)) &&
      actual == tag,
    )
  }
}

///|
test "Local sort take preserves numeric zero ties and null placement" {
  let input = duckdb_fixed_values(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true},\"tag\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":0,\"tag\":0},{\"k\":null,\"tag\":1},{\"k\":-1,\"tag\":2},{\"k\":0,\"tag\":3}]},\"as\":\"seed\"}]",
    steps="[{\"sort\":[{\"field\":\"k\",\"dir\":\"desc\",\"nulls\":\"last\"}]},{\"take\":3}]",
  )
  let owner = @execution.producer_read_receiver(input)
  let completed = @execution.execute_fixed_producers_guarded(
    compute_test_sequence(owner),
    [input],
    Step(1),
    compute_test_limits(),
    max_rows=100,
    max_value_bytes=1000,
    { max_nodes: 10000, max_bytes: 100000, max_depth: 100, max_work: 100000, },
  ).unwrap()
  let output = @execution.completed_output(completed, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  for (row, key, tag) in [(0, 0.0, 0.0), (1, 0.0, 3.0), (2, -1.0, 2.0)] {
    assert_true(
      @execution.completed_cell(output, row, 0) is Some(Number(actual)) &&
      actual == key,
    )
    assert_true(
      @execution.completed_cell(output, row, 1) is Some(Number(actual)) &&
      actual == tag,
    )
  }
}
