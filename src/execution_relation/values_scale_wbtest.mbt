///|
fn values_scale_sample(count : Int, width : Int) -> (Int, Int) raise {
  let payload = "x".repeat(width)
  let rows = Array::makei(count, _ => {
    "{\"x\":{\"literal\":\"" + payload + "\"}}"
  })
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"x\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]},\"as\":\"out\"}]",
  )
  let prepared = @lower.bound_preparation(owner)
  let id = @lower.node_id(@lower.node_at(prepared, 0).unwrap())
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    [id],
    {
      ..run_limits(),
      max_rows: count,
      metadata_entries: count * 8 + 100,
      retained_entries: count * 8 + 100,
      operation_entries: count * 8 + 100,
    },
    control,
  ).unwrap()
  let store = test_row_store(result)
  assert_eq(store.tables[0].unwrap().table.rows.length(), count)
  let sample = (maximum - control.remaining, store.workspace.peak)
  clear_table_store(store)
  sample
}

///|
test "values execution work and retained slots scale with rows and bytes" {
  let small = values_scale_sample(8, 8)
  let rows = values_scale_sample(64, 8)
  let bytes = values_scale_sample(8, 256)

  assert_true(rows.0 > small.0)
  assert_true(rows.1 > small.1)
  assert_true(rows.0 < small.0 * 9)
  assert_true(rows.1 < small.1 * 9)

  // The fixed params already own the admitted strings. Execution retains those
  // values without copying their bytes, so width changes neither logical row
  // work nor retained slot count at this boundary.
  assert_eq(bytes.0, small.0)
  assert_eq(bytes.1, small.1)
  assert_true(bytes.0 < small.0 * 12)
}
