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
  assert_eq(stream.row_measurements.unwrap().count, 0)
  assert_true(finish_managed_output_values(stream) is Err(Closed))
}

///|
test "managed row measurement index has fixed capacity and exact cells" {
  assert_eq(managed_row_measurement_capacity_bytes(0), Some(512L))
  assert_eq(managed_row_measurement_capacity_bytes(3), Some(539L))
  assert_true(managed_row_measurement_capacity_bytes(-1) is None)
  assert_true(managed_row_measurement_capacity_bytes(238609295) is None)
  let index = new_managed_row_measurements(3).unwrap()
  assert_eq(index.cells.length(), 27)
  assert_true(managed_row_measurement_push(index, (1, 2, false)))
  assert_true(
    managed_row_measurement_push(index, (2147483647, 2147483646, true)),
  )
  assert_eq(managed_row_measurement_get(index, 0), Some((1, 2, false)))
  assert_eq(
    managed_row_measurement_get(index, 1),
    Some((2147483647, 2147483646, true)),
  )
  assert_true(managed_row_measurement_get(index, 2) is None)
  assert_false(managed_row_measurement_set(index, 3, (1, 1, false)))
  discard_managed_row_measurements(index)
  assert_eq(index.count, 0)
  assert_eq(index.cells.length(), 0)
}

///|
test "retained measurement index revocation clears its backing allocation once" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receipt = source.material.receipt
  assert_eq(managed_output_measurement_index_cells(receipt), Some(4))
  assert_true(discard_managed_output_measurement_index(receipt))
  assert_true(managed_output_measurement_index_cells(receipt) is None)
  assert_false(discard_managed_output_measurement_index(receipt))
  let receiver = typed_receiver(owner, "[{\"filter\":\"n > 0\"}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  assert_true(
    managed_view_selection_measurements(plan, [0], 100) is Err(MissingIndex),
  )
}

///|
test "ordered occurrence selection avoids duplicate-map pass while permutations charge it" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"filter\":\"n > 0\"}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  // Two row checks + two column entries + four cell measurements.
  let ordered = managed_view_selection_measurements(plan, [0, 1], 8).unwrap()
  assert_true(
    managed_view_selection_measurements(plan, [0, 1], 7) is Err(Limit),
  )
  assert_true(
    managed_view_selection_measurements(plan, [1, 0], 8) is Err(Limit),
  )
  let permuted = managed_view_selection_measurements(plan, [1, 0], 10).unwrap()
  for column in 0..<2 {
    assert_eq(ordered[column].unwrap().bytes, permuted[column].unwrap().bytes)
    assert_eq(ordered[column].unwrap().nodes, permuted[column].unwrap().nodes)
  }
  assert_true(
    managed_view_selection_measurements(plan, [1, 1], 100)
    is Err(InvalidSelection),
  )
}
