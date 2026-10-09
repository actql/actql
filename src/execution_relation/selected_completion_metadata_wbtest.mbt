///|
fn selected_metadata_filter(
  name_bytes : Int,
) -> BoundedBindingRowsExecution raise {
  indexed_snapshot_fixture(
    "x".repeat(128) + "😀é",
    operation=Some(order_metadata_operation("\"filter\":\"id > 0\"")),
    binding=true,
    selected=true,
    name_bytes~,
  )
}

///|
test "selected filter reuses exact Unicode metadata and transfers one canonical names array" {
  // where_0 twice=14, id=2, 128 ASCII+emoji+accent=134: exactly 150.
  for quantum in [1, 7, 256] {
    let active = selected_metadata_filter(150)
    let cursor = active.state.port_preparation.unwrap()
    let names = active.state.output_names
    assert_true(active.state.output_names.is_empty())
    assert_true(
      advance_bounded_binding_rows(active, 1).unwrap()
      is BoundedBindingRowsContinue(work=1L, ..),
    )
    assert_eq((cursor.phase, cursor.bytes), (4, 0))
    assert_true(active.state.port is None)
    assert_true(
      finish_trusted_output_preparation(cursor, fn(_ : Unit) { None })
      is Err(Unverified),
    )
    assert_true(
      finish_selected_trusted_output_preparation(cursor, [], fn(_ : Unit) {
        None
      })
      is Err(Unverified),
    )
    let output = finish_order_metadata_fixture(active, quantum)
    assert_eq(completed_row_count(output), 1)
    assert_eq(completed_column_name(output, 0), Some("id"))
    assert_eq(
      completed_column_name(output, 1),
      Some("x".repeat(128) + "😀é"),
    )
    assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
    assert_true(completed_cell(output, 0, 1) is Some(Number(7)))
    assert_true(cursor.closed)
    assert_true(active.state.output_names.is_empty())
    assert_true(active.state.port_preparation is None)
    assert_true(physical_equal(active.state.port.unwrap().names, names))
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_false(cleanup_bounded_binding_rows(active).unwrap())
    assert_eq(active.state.workspace.live, 0)
    cancel_trusted_output_preparation(cursor)
    assert_eq(
      completed_column_name(output, 1),
      Some("x".repeat(128) + "😀é"),
    )
    assert_true((active.state.available)())
  }
}

///|
test "selected metadata checks each current byte and entry policy before input work" {
  let active = selected_metadata_filter(149)
  let cursor = active.state.port_preparation.unwrap()
  assert_true(
    advance_bounded_binding_rows(active, 1).unwrap()
    is BoundedBindingRowsFailed(Completion(Limit), work=1L, ..),
  )
  assert_eq(active.state.input_values.nodes, 0)
  assert_true(active.state.input_names.is_empty())
  assert_true(active.state.output_names.is_empty())
  assert_true(active.state.rows.val is None)
  assert_true((active.state.available)())
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
  // The same immutable owner cannot remember a previous permissive policy.
  for
    (entries, bytes, success) in [
      (2, 150, true),
      (2, 149, false),
      (1, 150, false),
    ] {
    let retry = start_trusted_output_preparation(
      cursor.generated,
      cursor.target,
      entries,
      bytes,
      None,
    ).unwrap()
    if success {
      assert_eq(reuse_selected_trusted_output_metadata(retry), Ok(true))
      assert_eq(retry.bytes, 0)
    } else {
      assert_eq(reuse_selected_trusted_output_metadata(retry), Err(Limit))
    }
    cancel_trusted_output_preparation(retry)
    assert_true(
      reuse_selected_trusted_output_metadata(retry) is Err(Unverified),
    )
  }
}

///|
test "selected filter cancellation preserves metadata custody before and after population" {
  for after_population in [false, true] {
    let active = selected_metadata_filter(150)
    let cursor = active.state.port_preparation.unwrap()
    if after_population {
      let mut reached = false
      for _ in 0..<10 {
        if !reached {
          assert_true(
            advance_bounded_binding_rows(active, 1).unwrap()
            is BoundedBindingRowsContinue(..),
          )
          reached = active.state.output_names.length() == 1
        }
      }
      assert_true(reached)
      assert_eq(cursor.phase, 4)
    }
    let work = active.state.control.remaining
    let held = active.state.workspace.live
    assert_true(@bounded.request_cancel(active.state.engine))
    assert_true(
      advance_bounded_binding_rows(active, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    assert_eq(active.state.control.remaining, work)
    assert_eq(active.state.workspace.live, held)
    assert_false(cursor.closed)
    assert_true(active.state.port is None)
    assert_true(active.state.rows.val is None)
    assert_true((active.state.available)())
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(cursor.closed)
    assert_true(active.state.output_names.is_empty())
    assert_eq(active.state.workspace.live, 0)
    assert_false(cleanup_bounded_binding_rows(active).unwrap())
  }
}

///|
test "selected append metadata preserves Unicode policy output names and borrowed inputs" {
  let name = "x".repeat(128) + "😀é"
  let schema = "{\"" + name + "\":{\"type\":\"number\",\"nullable\":false}}"
  // append_0 twice=16, original UTF-8 field spelling=134.
  for bytes in [150, 149] {
    let (_, result, reads) = bounded_append_fixture(
      selected=true,
      left_schema=schema,
      right_schema=schema,
      left_rows="[{\"" + name + "\":1}]",
      right_rows="[{\"" + name + "\":2}]",
      name_bytes=bytes,
    )
    let active = result.unwrap()
    let cursor = active.state.port_preparation.unwrap()
    let names = active.state.names
    if bytes == 149 {
      assert_true(
        advance_bounded_append(active, 1).unwrap()
        is BoundedAppendFailed(Completion(Limit), work=1L, ..),
      )
      assert_eq(active.state.input_scan.budget.nodes, 0)
      assert_true(active.state.rows.val is None)
    } else {
      let mut output = None
      for _ in 0..<5000 {
        if output is None {
          match advance_bounded_append(active, 1).unwrap() {
            BoundedAppendContinue(..) => ()
            BoundedAppendComplete(value, ..) => output = Some(value)
            _ => fail("exact selected Append metadata failed")
          }
        }
      }
      let output = output.unwrap()
      assert_eq(completed_row_count(output), 2)
      assert_eq(completed_column_name(output, 0), Some(name))
      assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
      assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
      assert_true(active.state.names.is_empty())
      assert_true(physical_equal(active.state.port.unwrap().names, names))
      assert_true(cleanup_bounded_append(active).unwrap())
      cancel_trusted_output_preparation(cursor)
      assert_eq(completed_column_name(output, 0), Some(name))
    }
    if bytes == 149 {
      assert_true(cleanup_bounded_append(active).unwrap())
    }
    assert_true(cursor.closed)
    assert_eq(active.state.workspace.live, 0)
    assert_false(cleanup_bounded_append(active).unwrap())
    assert_true(reads.all(producer_read_available))
  }
}

///|
test "selected metadata never substitutes for live receiving-input authority" {
  let live = Ref(true)
  let (_, result, reads) = bounded_append_fixture(
    selected=true,
    left_live=Some(live),
  )
  let active = result.unwrap()
  assert_true(
    advance_bounded_append(active, 1).unwrap() is BoundedAppendContinue(..),
  )
  assert_eq(active.state.port_preparation.unwrap().phase, 4)
  live.val = false
  assert_true(
    advance_bounded_append(active, 1).unwrap()
    is BoundedAppendFailed(InvalidExecution, ..),
  )
  assert_true(active.state.rows.val is None)
  assert_true(active.state.port is None)
  assert_true(cleanup_bounded_append(active).unwrap())
  assert_true(producer_read_available(reads[1]))
  assert_eq(active.state.workspace.live, 0)
}

///|
test "selected append cancellation keeps populated metadata until confirmed cleanup" {
  let (control, result, reads) = bounded_append_fixture(selected=true)
  let active = result.unwrap()
  let cursor = active.state.port_preparation.unwrap()
  let mut reached = false
  for _ in 0..<100 {
    if !reached {
      assert_true(
        advance_bounded_append(active, 1).unwrap() is BoundedAppendContinue(..),
      )
      reached = active.state.names.length() == 1
    }
  }
  assert_true(reached)
  assert_eq(cursor.phase, 4)
  let held = active.state.workspace.live
  let remaining = active.state.control.remaining
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_append(active, 1).unwrap() is BoundedAppendStopped(_, ..),
  )
  assert_eq(active.state.names, ["id"])
  assert_eq(active.state.workspace.live, held)
  assert_eq(active.state.control.remaining, remaining)
  assert_false(cursor.closed)
  assert_true(active.state.rows.val is None)
  assert_true(active.state.port is None)
  assert_true(reads.all(producer_read_available))
  assert_true(cleanup_bounded_append(active).unwrap())
  assert_false(cleanup_bounded_append(active).unwrap())
  assert_true(cursor.closed)
  assert_true(active.state.names.is_empty())
  assert_eq(active.state.workspace.live, 0)
  assert_true(reads.all(producer_read_available))
}

///|
test "selected non-filter metadata retains its original scalar cursor" {
  let active = indexed_snapshot_fixture("x".repeat(256), selected=true)
  let cursor = active.state.port_preparation.unwrap()
  assert_true(
    advance_bounded_binding_rows(active, 1).unwrap()
    is BoundedBindingRowsContinue(..),
  )
  assert_eq((cursor.phase, cursor.offset), (0, 1))
  assert_true(@bounded.request_cancel(active.state.engine))
  assert_true(
    advance_bounded_binding_rows(active, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
  assert_true(cursor.closed)
}
