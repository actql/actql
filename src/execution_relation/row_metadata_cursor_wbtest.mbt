///|
test "row metadata lookup preserves qualified UTF16 spelling and bounded scans" {
  let name = "x".repeat(128) + "😀é"
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Qualified(@schema.Left, name), contract),
      (@schema.Qualified(@schema.Right, name), contract),
    ],
    max_fields=2,
    max_name_bytes=1000,
  ).unwrap()
  for quantum in [1, 7, 256] {
    for
      (field, expected) in [
        (@schema.Unqualified("left." + name), 0),
        (@schema.Qualified(@schema.Right, name), 1),
        (@schema.Qualified(@schema.Left, "x".repeat(128) + "😀é"), -1),
      ] {
      let workspace = row_workspace(1)
      let cursor = start_row_metadata_lookup(schema, field, workspace).unwrap()
      let mut result = None
      for _ in 0..<100 {
        for _ in 0..<quantum {
          if result is None {
            result = advance_row_metadata_lookup(cursor)
          }
        }
      }
      assert_eq(result, Some(expected))
      assert_eq((workspace.peak, workspace.live), (1, 0))
      close_row_metadata_lookup(cursor)
      assert_eq(workspace.live, 0)
    }
  }
  let workspace = row_workspace(1)
  let cursor = start_row_metadata_lookup(
    schema,
    @schema.Qualified(@schema.Left, name),
    workspace,
  ).unwrap()
  assert_true(advance_row_metadata_lookup(cursor) is None)
  assert_eq(cursor.offset, 64)
  close_row_metadata_lookup(cursor)
  close_row_metadata_lookup(cursor)
  assert_eq(workspace.live, 0)
  assert_eq(advance_row_metadata_lookup(cursor), Some(-1))
  assert_true(
    start_row_metadata_lookup(
      schema,
      @schema.Qualified(@schema.Left, name),
      row_workspace(0),
    )
    is None,
  )
}

///|
test "large Relation metadata is not materialized before bounded resume" {
  let execution = indexed_snapshot_fixture("x".repeat(256))
  assert_eq(
    execution.state.input_names.length(),
    0,
    msg="start must not flatten or copy the complete input name array",
  )
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsContinue(..),
  )
  assert_true(execution.state.input_names.length() <= 1)
  @bounded.request_cancel(execution.state.engine) |> ignore
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  assert_eq(execution.state.workspace.live, 0)
  assert_true((execution.state.available)())
}

///|
test "expression metadata preparation stops during each owned phase" {
  for target in [0, 1, 2, 3] {
    let execution = indexed_snapshot_fixture(
      "x".repeat(256),
      derive_name=if target == 2 { "x".repeat(256) + "next" } else { "next" },
    )
    let mut reached = false
    for _ in 0..<100 {
      if !reached {
        assert_true(
          advance_bounded_binding_rows(execution, 1).unwrap()
          is BoundedBindingRowsContinue(..),
        )
        reached = match execution.state.phase {
          PrepareInputNames => target == 0
          PrepareOutputNames => target == 1
          PrepareRowSources =>
            if target == 2 {
              execution.state.metadata_offset == 64
            } else if target == 3 {
              match execution.state.metadata_lookup {
                Some(cursor) => cursor.offset == 64
                None => false
              }
            } else {
              false
            }
          _ => false
        }
      }
    }
    assert_true(reached)
    let remaining = execution.state.control.remaining
    @bounded.request_cancel(execution.state.engine) |> ignore
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(
      (execution.state.control.remaining, execution.state.workspace.live),
      (remaining, 0),
    )
    assert_true(execution.state.metadata_lookup is None)
    assert_true(execution.state.input_names.is_empty())
    assert_true(execution.state.output_names.is_empty())
    assert_true(execution.state.row_sources.is_empty())
    assert_true((execution.state.available)())
  }
}

///|
test "indexed projection prepares sources in bounded fragments and stops before reading" {
  let name = "x".repeat(256)
  let execution = indexed_snapshot_fixture(name, projection=true)
  assert_true(execution.state.input_names.is_empty())
  assert_true(execution.state.output_names.is_empty())
  let mut reached = false
  for _ in 0..<100 {
    if !reached {
      assert_true(
        advance_bounded_binding_rows(execution, 1).unwrap()
        is BoundedBindingRowsContinue(..),
      )
      reached = execution.state.metadata_offset == 64
    }
  }
  assert_true(reached)
  assert_true(execution.state.phase is PrepareRowSources)
  assert_eq(execution.state.input_values.nodes, 0)
  @bounded.request_cancel(execution.state.engine) |> ignore
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  assert_eq(execution.state.workspace.live, 0)
  assert_true((execution.state.available)())
}

///|
test "metadata resume quantum preserves expression and projection rows and charges" {
  let name = "x".repeat(256)
  for projection in [false, true] {
    let mut reference : (Int, Int64, Int)? = None
    for quantum in [1, 7, 256] {
      let execution = indexed_snapshot_fixture(name, projection~)
      let mut completed : CompletedOutput? = None
      for _ in 0..<6000 {
        if completed is None {
          match advance_bounded_binding_rows(execution, quantum).unwrap() {
            BoundedBindingRowsContinue(..) => ()
            BoundedBindingRowsComplete(output, ..) => completed = Some(output)
            _ => fail("metadata preparation did not complete")
          }
        }
      }
      let output = completed.unwrap()
      assert_eq(completed_row_count(output), 1)
      if projection {
        assert_true(completed_cell(output, 0, 0) is Some(Number(7)))
      } else {
        assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
        assert_true(completed_cell(output, 0, 1) is Some(Number(2)))
        assert_true(completed_cell(output, 0, 2) is Some(Number(7)))
      }
      let charges = (
        execution.state.control.remaining,
        execution.state.logical.map(b => b.work).unwrap_or(0L),
        execution.state.workspace.peak,
      )
      match reference {
        Some(expected) => assert_eq(charges, expected)
        None => reference = Some(charges)
      }
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}
