///|
test "contiguous retained selection matches explicit occurrences without an array map" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live, index_cells=4)
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
  for start in 0..<3 {
    for count in 0..<(3 - start) {
      let slice = prepare_managed_view_slice(plan, start, count, 4, 100).unwrap()
      let explicit = prepare_managed_view_selection(
        plan,
        Array::makei(count, i => start + i),
        4,
        100,
      ).unwrap()
      assert_true(slice.rows is Slice(_, _))
      assert_eq(slice.index.cells, explicit.index.cells)
      assert_eq(slice.facts.rows, count)
      for column in 0..<2 {
        let actual = slice.facts.columns[column]
        let expected = explicit.facts.columns[column]
        assert_eq(
          (actual.bytes, actual.nodes, actual.null_rows),
          (expected.bytes, expected.nodes, expected.null_rows),
        )
      }
      for row in 0..<count {
        assert_eq(managed_view_selection_row(slice, row), Some(start + row))
      }
      assert_true(managed_view_selection_row(slice, -1) is None)
      assert_true(managed_view_selection_row(slice, count) is None)
      let stream = prepare_managed_output_values(
        receiver,
        Step(0),
        2,
        stream_value_limits(),
        100,
        managed_test_measure_limits(),
      ).unwrap()
      let port = prepare_managed_selected_view_output_port(slice, stream, (
        _ : Unit,
      ) => true).unwrap()
      let receipt = finish_managed_view_output(port, ()).unwrap()
      assert_eq(
        managed_output_measurement_index_cells(receipt),
        Some(count * 2),
      )
    }
  }
  // Slice does not pay for a defensive occurrence-array copy.
  assert_true(prepare_managed_view_slice(plan, 0, 2, 4, 12) is Ok(_))
  assert_true(prepare_managed_view_slice(plan, 0, 2, 4, 11) is Err(Limit))
  assert_true(prepare_managed_view_selection(plan, [0, 1], 4, 12) is Err(Limit))
  for (start, count) in [(-1, 1), (0, -1), (3, 0), (2, 1), (1, 2147483647)] {
    assert_true(
      prepare_managed_view_slice(plan, start, count, 4, 100)
      is Err(InvalidSelection),
    )
  }
  assert_true(prepare_managed_view_slice(plan, 0, 2, 3, 100) is Err(Limit))
  live.val = false
  assert_true(
    prepare_managed_view_slice(plan, 0, 2, 4, 100) is Err(ForeignInput),
  )
}

///|
test "slice cannot discard rows from an all-rows checked view" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"select\":[\"s\"]}]")
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
    prepare_managed_view_slice(plan, 0, 1, 2, 100) is Err(InvalidSelection),
  )
  assert_true(
    prepare_managed_view_slice(plan, 2, 0, 2, 100) is Err(InvalidSelection),
  )
  assert_true(prepare_managed_view_slice(plan, 0, 2, 2, 100) is Ok(_))
}
