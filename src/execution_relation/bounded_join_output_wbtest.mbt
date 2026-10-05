///|
fn join_large_output_limits() -> ValueLimits {
  // One outer object and three cells; names k/l/r add three bytes.
  // Two copied 4096-byte Text values therefore cost 8195 bytes and 8199 work.
  { max_nodes: 4, max_text_bytes: 8195, max_depth: 2, max_work: 8199, }
}

///|
fn join_large_output_fixture(
  limits : ValueLimits,
  max_entries? : Int = 1000,
) -> (@bounded.Control, BoundedJoinExecution, Array[ProducerRead]) raise {
  let row = "[{\"id\":1,\"v\":\"" + "x".repeat(4096) + "\"}]"
  let fixture = bounded_join_fixture(
    left_rows=row,
    right_rows=row,
    value_type="string",
    output_nodes=limits.max_nodes,
    output_values=limits,
    max_entries~,
  )
  // Generated Values completion is a RowTable, not a reusable admitted cell.
  assert_true(producer_read_admitted_cell(fixture.2[0], 0, 1) is None)
  fixture
}

///|
test "bounded join yields before completing raw large output validation" {
  let (control, active, reads) = join_large_output_fixture(
    join_large_output_limits(),
  )
  let mut reached = false
  for _ in 0..<50000 {
    if active.state.phase is BuildCell && active.state.column == 1 {
      reached = true
      break
    }
    assert_true(
      advance_bounded_join(active, 1).unwrap() is BoundedJoinContinue(..),
    )
  }
  assert_true(reached)
  assert_true(
    advance_bounded_join(active, 1).unwrap() is BoundedJoinContinue(..),
  )
  // A single poll must not finish recursive validation of the raw Text cell.
  assert_true(active.state.pending is None)
  assert_true(
    advance_bounded_join(active, 1).unwrap() is BoundedJoinContinue(..),
  )
  assert_true(active.state.pending is None)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_join(active, 1).unwrap() is BoundedJoinStopped(_, ..),
  )
  assert_true(active.state.rows.val is None)
  assert_true(reads.all(read => producer_read_available(read)))
  assert_true(cleanup_bounded_join(active).unwrap())
  assert_eq(active.state.workspace.live, 0)
  assert_true(active.state.output_recheck is None)
  assert_true(active.state.checked_row.is_empty())
  assert_true(active.state.pending is None)
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
test "bounded join raw output keeps independent exact and one-short limits" {
  for short in -1..<3 {
    let exact = join_large_output_limits()
    let limits = {
      max_nodes: exact.max_nodes - (if short == 0 { 1 } else { 0 }),
      max_text_bytes: exact.max_text_bytes - (if short == 1 { 1 } else { 0 }),
      max_depth: exact.max_depth,
      max_work: exact.max_work - (if short == 2 { 1 } else { 0 }),
    }
    let (_, active, reads) = join_large_output_fixture(limits)
    let result = finish_bounded_join_test(active)
    if short == -1 {
      let output = result.unwrap()
      assert_eq(completed_row_count(output), 1)
      assert_true(
        completed_cell(output, 0, 0) is Some(Number(number)) && number == 1,
      )
      for column in [1, 2] {
        assert_true(
          completed_cell(output, 0, column) is Some(Text(text)) &&
          text == "x".repeat(4096),
        )
      }
    } else {
      assert_true(result is Err(Capture(CaptureLimit)))
      assert_true(active.state.rows.val is None)
    }
    assert_true(cleanup_bounded_join(active).unwrap())
    assert_eq(active.state.workspace.live, 0)
    assert_true(active.state.output_recheck is None)
    assert_true(reads.all(read => producer_read_available(read)))
  }
}

///|
test "bounded join raw output reserves exact overlapping workspace" {
  // Same three-field layout as the independent scalar Join fixture:
  // base 2 + key mapping/order 3 + projection metadata 9 + NULL flags 2
  // + retained right index 1 + row handles 2 + cells 3 + measure frames 2.
  let exact = 2 + 3 + 9 + 2 + 1 + 2 + 3 + 2
  for limit in [exact - 1, exact] {
    let (_, active, reads) = join_large_output_fixture(
      join_large_output_limits(),
      max_entries=limit,
    )
    let result = finish_bounded_join_test(active)
    if limit == exact {
      assert_eq(completed_row_count(result.unwrap()), 1)
      assert_eq(active.state.workspace.peak, exact)
    } else {
      assert_true(result is Err(Rows(RowLimit)))
      assert_true(active.state.rows.val is None)
    }
    assert_true(cleanup_bounded_join(active).unwrap())
    assert_eq(active.state.workspace.live, 0)
    assert_true(active.state.output_recheck is None)
    assert_true(reads.all(read => producer_read_available(read)))
  }
}
