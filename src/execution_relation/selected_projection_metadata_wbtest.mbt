///|
fn selected_projection_metadata_fixture(
  body : String,
  bytes : Int,
) -> BoundedBindingRowsExecution raise {
  indexed_snapshot_fixture(
    "x".repeat(128) + "😀é",
    projection=true,
    operation=Some(order_metadata_operation(body)),
    selected=true,
    name_bytes=bytes,
  )
}

///|
test "selected projections reuse exact output schema bytes and transfer canonical names" {
  let name = "x".repeat(128) + "😀é"
  // Original spelling is 134 UTF-8 bytes. The policy counts the output
  // schema, never the wider input or the authored projection ordering.
  for
    (body, names, values, bytes) in [
      ("\"select\":[\"" + name + "\",\"id\"]", ["id", name], [1.0, 7.0], 152),
      (
        "\"rename\":{\"" + name + "\":\"alias\"}",
        ["alias", "id"],
        [7.0, 1.0],
        23,
      ),
      ("\"drop\":[\"id\"]", [name], [7.0], 150),
    ] {
    // Select, rename and drop all lower to select_0, counted twice (16).
    for quantum in [1, 7, 256] {
      let active = selected_projection_metadata_fixture(body, bytes)
      let cursor = active.state.port_preparation.unwrap()
      let canonical_names = active.state.output_names
      assert_true(canonical_names.is_empty())
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
      let output = finish_order_metadata_fixture(active, quantum)
      assert_eq(completed_row_count(output), 1)
      assert_eq(completed_column_count(output), names.length())
      for column, name in names {
        assert_eq(completed_column_name(output, column), Some(name))
        assert_true(
          completed_cell(output, 0, column) is Some(Number(value)) &&
          value == values[column],
        )
      }
      assert_true(
        physical_equal(active.state.port.unwrap().names, canonical_names),
      )
      assert_true(active.state.output_names.is_empty())
      assert_true(cleanup_bounded_binding_rows(active).unwrap())
      assert_false(cleanup_bounded_binding_rows(active).unwrap())
      assert_eq(active.state.workspace.live, 0)
      cancel_trusted_output_preparation(cursor)
      for column, name in names {
        assert_eq(completed_column_name(output, column), Some(name))
      }
      assert_true((active.state.available)())
    }
    let short = selected_projection_metadata_fixture(body, bytes - 1)
    let cursor = short.state.port_preparation.unwrap()
    assert_true(
      advance_bounded_binding_rows(short, 1).unwrap()
      is BoundedBindingRowsFailed(Completion(Limit), work=1L, ..),
    )
    assert_eq(short.state.input_values.nodes, 0)
    assert_true(short.state.input_names.is_empty())
    assert_true(short.state.output_names.is_empty())
    assert_true(short.state.rows.val is None)
    assert_true(cleanup_bounded_binding_rows(short).unwrap())
    let retry = start_trusted_output_preparation(
      cursor.generated,
      cursor.target,
      0,
      bytes,
      None,
    ).unwrap()
    assert_eq(reuse_selected_trusted_output_metadata(retry), Err(Limit))
    cancel_trusted_output_preparation(retry)
  }
}

///|
test "selected projection cancellation retains names until confirmed cleanup" {
  let name = "x".repeat(128) + "😀é"
  for
    body in [
      "\"select\":[\"" + name + "\"]",
      "\"rename\":{\"" + name + "\":\"alias\"}",
      "\"drop\":[\"id\"]",
    ] {
    for after_population in [false, true] {
      let active = selected_projection_metadata_fixture(body, 1000)
      let cursor = active.state.port_preparation.unwrap()
      assert_true(
        advance_bounded_binding_rows(active, 1).unwrap()
        is BoundedBindingRowsContinue(work=1L, ..),
      )
      if after_population {
        let mut reached = false
        for _ in 0..<100 {
          if !reached {
            assert_true(
              advance_bounded_binding_rows(active, 1).unwrap()
              is BoundedBindingRowsContinue(..),
            )
            reached = active.state.output_names.length() == 1
          }
        }
        assert_true(reached)
      }
      assert_eq(cursor.phase, 4)
      let remaining = active.state.control.remaining
      let held = active.state.workspace.live
      assert_true(@bounded.request_cancel(active.state.engine))
      assert_true(
        advance_bounded_binding_rows(active, 1).unwrap()
        is BoundedBindingRowsStopped(_, ..),
      )
      assert_eq(active.state.control.remaining, remaining)
      assert_eq(active.state.workspace.live, held)
      assert_eq(
        active.state.output_names.length(),
        if after_population {
          1
        } else {
          0
        },
      )
      assert_false(cursor.closed)
      assert_true(active.state.rows.val is None)
      assert_true(active.state.port is None)
      assert_true(cleanup_bounded_binding_rows(active).unwrap())
      assert_true(cursor.closed)
      assert_true(active.state.output_names.is_empty())
      assert_eq(active.state.workspace.live, 0)
      assert_false(cleanup_bounded_binding_rows(active).unwrap())
      assert_true((active.state.available)())
    }
  }
}
