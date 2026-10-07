///|
test "bounded output port name refusal is observed before any row is evaluated" {
  // Two occurrences of 'derive_0' (16 bytes), 'id' (2), 'next' (4),
  // and the 256-byte input spelling give an independent exact bound of 278.
  let execution = indexed_snapshot_fixture("x".repeat(256), name_bytes=277)
  let mut refused = false
  for _ in 0..<1000 {
    if !refused {
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsFailed(Completion(Limit), ..) => refused = true
        _ => fail("expected completion name limit")
      }
    }
  }
  assert_true(refused)
  assert_eq(execution.state.row, 0)
  assert_true(execution.state.rows.val is None)
  assert_false(execution.state.accepted.val)
  assert_true((execution.state.available)())
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "bounded output port preparation borrows Unicode names within exact bytes" {
  // derive_0 twice = 16, id = 2, next = 4, and 256 ASCII + emoji = 260.
  // Name admission therefore requires exactly 282 UTF-8 bytes.
  let name = "x".repeat(256) + "😀"
  let mut usage : (Int, Int, Int)? = None
  for quantum in [1, 7, 256] {
    let execution = indexed_snapshot_fixture(name, name_bytes=282)
    let cursor = execution.state.port_preparation.unwrap()
    assert_eq(cursor.id, "derive_0")
    assert_true(cursor.names.is_empty())
    assert_eq((cursor.offset, cursor.bytes), (0, 282))
    assert_true(execution.state.port is None)
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsContinue(work=1, ..),
    )
    assert_eq((cursor.offset, cursor.bytes), (1, 281))
    assert_true(execution.state.input_names.is_empty())
    let output = finish_order_metadata_fixture(execution, quantum)
    assert_eq(completed_row_count(output), 1)
    assert_eq(completed_column_name(output, 0), Some("id"))
    assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
    assert_eq(completed_column_name(output, 1), Some("next"))
    assert_true(completed_cell(output, 0, 1) is Some(Number(2.0)))
    assert_eq(completed_column_name(output, 2), Some(name))
    assert_true(completed_cell(output, 0, 2) is Some(Number(7.0)))
    assert_eq(cursor.bytes, 0)
    assert_true(execution.state.port_preparation is None)
    assert_true(cursor.closed)
    let actual = (
      execution.state.control.remaining,
      execution.state.output_values.work,
      execution.state.workspace.peak,
    )
    if usage is Some(expected) {
      assert_eq(actual, expected)
    }
    usage = Some(actual)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    // Successful transfer must not clear the names kept by the completion.
    assert_eq(cursor.names.length(), 3)
    cancel_trusted_output_preparation(cursor)
    assert_eq(cursor.names.length(), 3)
    assert_eq(completed_column_name(output, 2), Some(name))
  }
}

///|
test "output port stops between name scalars without releasing borrowed input" {
  for phase in [0, 1, 2, 3] {
    let execution = indexed_snapshot_fixture("x".repeat(256))
    let cursor = execution.state.port_preparation.unwrap()
    let mut entered = false
    for _ in 0..<1000 {
      if !entered {
        if cursor.phase == phase && cursor.offset > 0 {
          entered = true
        } else {
          assert_true(
            advance_bounded_binding_rows(execution, 1).unwrap()
            is BoundedBindingRowsContinue(..),
          )
        }
      }
    }
    assert_true(entered)
    let held = execution.state.workspace.live
    let remaining = execution.state.control.remaining
    assert_true(@bounded.request_cancel(execution.state.engine))
    assert_true((execution.state.available)())
    assert_eq(execution.state.workspace.live, held)
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    assert_false(cursor.closed)
    assert_true(execution.state.port is None)
    assert_true(execution.state.rows.val is None)
    assert_eq(execution.state.control.remaining, remaining)
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_false(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(cursor.closed)
    assert_true(cursor.names.is_empty())
    assert_true(execution.state.port_preparation is None)
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}

///|
test "output port partial preparation cannot issue a completion" {
  let execution = indexed_snapshot_fixture("x".repeat(256))
  let cursor = execution.state.port_preparation.unwrap()
  assert_true(
    finish_trusted_output_preparation(cursor, fn(_ : Unit) { None })
    is Err(Unverified),
  )
  assert_true(@bounded.request_cancel(execution.state.engine))
  advance_bounded_binding_rows(execution, 1).unwrap() |> ignore
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  assert_true(advance_trusted_output_preparation(cursor) is Err(Unverified))
  assert_true(
    finish_trusted_output_preparation(cursor, fn(_ : Unit) { None })
    is Err(Unverified),
  )
}
