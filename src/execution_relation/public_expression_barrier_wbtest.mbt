///|
test "public retained filter fixture exposes its actual long Text scanning quantum" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"tag\":\"" + String::make(256, 'g') + "\"}]",
    compare_text=true,
    fragment_rows=1L,
  )
  for _ in 0..<3 {
    assert_true(
      advance_bounded_binding_rows(execution, 256).unwrap()
      is BoundedBindingRowsContinue(progress=0L, ..),
    )
  }
  guard execution.state.predicate_execution is Some(frame) &&
    frame.state is CompareBinary(comparison) else {
    fail("public comparison barrier did not reach the predicate frame")
  }
  assert_eq(comparison.phase, 2)
  assert_true(comparison.offset > 64 && comparison.offset < 256)
  let logical = execution.state.logical.unwrap()
  let consumed = logical.work
  let remaining = execution.state.control.remaining
  let held = execution.state.workspace.live
  let root = execution.state.input_roots[0]
  assert_false(root.root.released)
  assert_true(frame.closed == false)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq(execution.state.workspace.live, held)
  assert_eq(logical.work, consumed)
  assert_false(root.root.released)
  assert_false(frame.closed)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(frame.closed)
  assert_true(root.root.released)
  assert_eq((logical.live, execution.state.workspace.live), (0L, 0))
  assert_eq(
    (logical.work, execution.state.control.remaining),
    (consumed, remaining),
  )
  assert_true(producer_read_available(input))
}

///|
test "public retained filter preserves logical work across Host polling quanta" {
  let mut prior : (Int, Int64)? = None
  for quantum in [1, 7, 256] {
    let (_, execution, input) = bounded_binding_rows_fixture(
      "[{\"id\":1,\"tag\":\"" + String::make(256, 'g') + "\"}]",
      compare_text=true,
      fragment_rows=1L,
    )
    let mut result : CompletedOutput? = None
    for _ in 0..<5000 {
      match advance_bounded_binding_rows(execution, quantum).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          result = Some(output)
          break
        }
        _ => fail("public filter fixture had an unrelated terminal outcome")
      }
    }
    guard result is Some(output) else {
      fail("public filter fixture did not terminate")
    }
    assert_eq(completed_row_count(output), 1)
    assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
    assert_true(completed_output_matches_inputs(output, [input]))
    let work = (
      execution.state.control.remaining,
      execution.state.logical.unwrap().work,
    )
    if prior is Some(expected) {
      assert_eq(work, expected)
    }
    prior = Some(work)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(
      (execution.state.logical.unwrap().live, execution.state.workspace.live),
      (0L, 0),
    )
    assert_true(producer_read_available(input))
  }
}
