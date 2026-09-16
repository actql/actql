///|
test "managed selected occurrences reuse original nonuniform measurements without values" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live, index_cells=4)
  assert_eq(
    managed_output_measurement_index_cells(source.material.receipt),
    Some(4),
  )
  let receiver = typed_receiver(
    owner, "[{\"filter\":\"n > 0\"},{\"derive\":{\"copy\":\"s\",\"new\":\"n + 1\"}},{\"select\":[\"copy\",\"n\",\"new\",\"s\"]}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    Array::makei(3, i => row_kernel(receiver, i)),
    1000,
    10000,
    100,
  ).unwrap()
  for (rows, expected) in [([0], 4), ([1], 6), ([1, 0], 10), ([], 0)] {
    let facts = managed_view_selection_measurements(plan, rows, 100).unwrap()
    assert_eq(facts[0].unwrap().bytes, expected)
    assert_eq(facts[3].unwrap().bytes, expected)
    assert_eq(facts[1].unwrap().nodes, rows.length())
    assert_true(facts[2] is None)
    assert_eq(facts[0].unwrap().null_rows, 0)
  }
  for rows in [[0, 0], [-1], [2]] {
    assert_true(
      managed_view_selection_measurements(plan, rows, 100)
      is Err(InvalidSelection),
    )
  }
  assert_true(managed_view_selection_measurements(plan, [1], 1) is Err(Limit))
  live.val = false
  assert_true(
    managed_view_selection_measurements(plan, [1], 100) is Err(ForeignInput),
  )
}

///|
test "managed row measurement index is optional bounded and sealed only on full admission" {
  let owner = capture_fixture()
  let plain = managed_read_fixture(owner, Ref(true))
  assert_true(
    managed_output_measurement_index_cells(plain.material.receipt) is None,
  )
  let receiver = typed_receiver(owner, "[{\"select\":[\"s\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, plain, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  assert_true(
    managed_view_selection_measurements(plan, [0, 1], 100) is Err(MissingIndex),
  )
  let stream = managed_retention_test_stream(owner)
  enable_managed_row_measurements(stream, 3).unwrap()
  assert_true(enable_managed_row_measurements(stream, 4) is Err(Closed))
  let first = output_fixture_row(owner, 0)
  append_managed_output_values(stream, 2, i => first.get(i)).unwrap()
  let reads = Ref(0)
  assert_true(
    append_managed_output_values(stream, 2, _ => {
      reads.val += 1
      None
    })
    is Err(MeasurementIndexLimit),
  )
  assert_eq(reads.val, 0)
  assert_true(stream.row_measurements.unwrap().cells.is_empty())
  assert_true(finish_managed_output_values(stream) is Err(Closed))
}
