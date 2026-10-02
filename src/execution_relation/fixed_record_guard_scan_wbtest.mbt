///|
test "record guard scan uses independent exact wire and work boundaries" {
  let owner = input_owner()
  let rows = capture_input(
    owner,
    0,
    [input_cursor("{\"n\":3,\"s\":\"ok\"}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, rows, fn() { true }).unwrap()
  // {"n":3,"s":"ok"}: 16 bytes, three value nodes, one container.
  // Row open, two column starts/emissions, column end, row end, scan end.
  for
    (work, ceiling, success) in [(8, 16, true), (7, 16, false), (8, 15, false)] {
    let scan = start_supplied_record_guard(
      @bounded.control(),
      read,
      ceiling,
      { max_work: work, max_bytes: 16, max_nodes: 3, max_depth: 1, },
      8,
    ).unwrap()
    let mut terminal = false
    for _ in 0..<20 {
      if terminal {
        break
      }
      match advance_fixed_record_guard(scan, 1).unwrap() {
        @bounded.ContinueWith(_, ..) => ()
        @bounded.Completed(remaining, work~, ..) => {
          assert_true(success)
          assert_eq(work, 8L)
          assert_eq(remaining.max_work, 0)
          assert_eq(remaining.max_bytes, 0)
          assert_eq(remaining.max_nodes, 0)
          terminal = true
        }
        @bounded.FailedWith(issue, ..) => {
          assert_false(success)
          if ceiling == 15 {
            assert_true(issue is ValueBytes(InputValues, 0, -1))
          } else {
            assert_true(issue is MeasurementWork)
          }
          terminal = true
        }
        _ => fail("unexpected record measurement stop")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_fixed_record_guard(scan).unwrap())
    assert_true(cleanup_fixed_record_guard(scan).unwrap())
    assert_true(supplied_relation_read_available(read))
  }
}

///|
test "record guard scan cancels inside a nested completed value" {
  let (_, output) = bounded_binding_rows_source(
    "[{\"id\":1,\"payload\":[1,2,3,4,5,6,7,8,9,10]}]",
    unused_payload=true,
  )
  let control = @bounded.control()
  let scan = start_completed_record_guard(
    control,
    output,
    1000,
    { max_work: 1000, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
    211,
  ).unwrap()
  // Reach the array emission; the entire nested value has not been drained.
  for _ in 0..<8 {
    assert_true(
      advance_fixed_record_guard(scan, 1).unwrap()
      is @bounded.ContinueWith(_, ..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_fixed_record_guard(scan, 1).unwrap()
    is @bounded.StoppedWith(Cancelled, work=8L, ..),
  )
  assert_true(cleanup_fixed_record_guard(scan).unwrap())
  assert_true(completed_output_available(output))
  assert_eq(completed_row_count(output), 1)
}
