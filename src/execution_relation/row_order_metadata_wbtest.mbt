///|
fn order_metadata_operation(body : String) -> String {
  "{" + body + ",\"from\":\"rows\",\"as\":\"derived\"}"
}

///|
test "ordered row metadata is resumed before names and maps are materialized" {
  let name = "x".repeat(256)
  for
    body in [
      "\"sort\":[{\"" + name + "\":\"asc\"}]",
      "\"take\":{\"count\":1,\"offset\":1}",
      "\"distinct\":true",
      "\"distinct\":[\"" + name + "\"]",
      "\"dedupe_rows\":{\"by\":[\"id\"],\"order_by\":[{\"" +
      name +
      "\":\"desc\"}]}",
      "\"assert_rows\":{\"unique_by\":[\"" + name + "\"]}",
      "\"top_k\":{\"k\":1,\"by\":[{\"" + name + "\":\"asc\"}]}",
      "\"top_k_by\":{\"partition_by\":[],\"k\":1,\"by\":[{\"" +
      name +
      "\":\"asc\"}]}",
    ] {
    let execution = indexed_snapshot_fixture(
      name,
      operation=Some(order_metadata_operation(body)),
      keyed=true,
    )
    assert_true(execution.state.input_names.is_empty())
    assert_true(execution.state.output_names.is_empty())
    @bounded.request_cancel(execution.state.engine) |> ignore
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}

///|
test "ordered metadata preserves independent rows and charges across resume quanta" {
  let name = "x".repeat(256)
  let rows = "[{\"id\":2,\"" +
    name +
    "\":8},{\"id\":1,\"" +
    name +
    "\":7},{\"id\":3,\"" +
    name +
    "\":9}]"
  for
    (body, ids) in [
      ("\"sort\":[{\"" + name + "\":\"asc\"}]", [1.0, 2.0, 3.0]),
      ("\"take\":{\"count\":1,\"offset\":1}", [1.0]),
      ("\"distinct\":true", [2.0, 1.0, 3.0]),
      (
        "\"dedupe_rows\":{\"by\":[\"id\"],\"order_by\":[{\"" +
        name +
        "\":\"desc\"}]}",
        [1.0, 2.0, 3.0],
      ),
      ("\"assert_rows\":{\"unique_by\":[\"" + name + "\"]}", [2.0, 1.0, 3.0]),
      ("\"top_k\":{\"k\":2,\"by\":[{\"" + name + "\":\"asc\"}]}", [1.0, 2.0]),
      (
        "\"top_k_by\":{\"partition_by\":[],\"k\":2,\"by\":[{\"" +
        name +
        "\":\"asc\"}]}",
        [1.0, 2.0],
      ),
    ] {
    let mut reference : (Int, Int)? = None
    for quantum in [1, 7, 256] {
      let execution = indexed_snapshot_fixture(
        name,
        operation=Some(order_metadata_operation(body)),
        rows=Some(rows),
        keyed=true,
      )
      let mut completed : CompletedOutput? = None
      for _ in 0..<12000 {
        if completed is None {
          match advance_bounded_binding_rows(execution, quantum).unwrap() {
            BoundedBindingRowsContinue(..) => ()
            BoundedBindingRowsComplete(output, ..) => completed = Some(output)
            BoundedBindingRowsFailed(_, ..) => fail("ordered metadata failed")
            _ => fail("unexpected ordered metadata stop")
          }
        }
      }
      let output = completed.unwrap()
      assert_eq(completed_row_count(output), ids.length())
      for row, id in ids {
        assert_true(
          completed_cell(output, row, 0) is Some(Number(actual)) && actual == id,
        )
        let value = if id == 1 { 7.0 } else if id == 2 { 8.0 } else { 9.0 }
        assert_true(
          completed_cell(output, row, 1) is Some(Number(actual)) &&
          actual == value,
        )
      }
      let charges = (
        execution.state.control.remaining,
        execution.state.workspace.peak,
      )
      match reference {
        None => reference = Some(charges)
        Some(expected) => assert_eq(charges, expected)
      }
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
test "long sort term has independently derived work and temporary workspace boundaries" {
  // Two input/output names + two input ordinals + two projection ordinals,
  // one sort term and two cached sources reserve eleven metadata slots.
  // Lookup and name charge each need one additional slot, never simultaneously.
  // The term pays one entry plus UTF8 bytes: ASCII 256, emoji 4 and e-acute 2.
  for
    (name, needed) in [
      ("x".repeat(256), 257),
      ("x".repeat(256) + "😀é", 263),
    ] {
    let body = order_metadata_operation("\"sort\":[{\"" + name + "\":\"asc\"}]")
    for
      (work, entries, success) in [
        (needed, 12, true),
        (needed - 1, 12, false),
        (needed, 11, false),
      ] {
      let execution = indexed_snapshot_fixture(
        name,
        operation=Some(body),
        work~,
        entries~,
      )
      assert_eq(execution.state.workspace.live, 11)
      let mut result : Result[Int?, RowIssue] = Ok(None)
      for _ in 0..<400 {
        if result is Ok(None) {
          result = advance_row_term_preparation(
            execution.state,
            @schema.Unqualified(name),
            0,
          )
        }
      }
      if success {
        assert_true(result is Ok(Some(1)))
        assert_eq(execution.state.control.remaining, 0)
        assert_eq(execution.state.workspace.peak, 12)
      } else {
        assert_true(result is Err(RowLimit))
      }
      @bounded.request_cancel(execution.state.engine) |> ignore
      advance_bounded_binding_rows(execution, 1) |> ignore
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
fn finish_order_metadata_fixture(
  execution : BoundedBindingRowsExecution,
  quantum : Int,
) -> CompletedOutput raise {
  for _ in 0..<12000 {
    match advance_bounded_binding_rows(execution, quantum).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => return output
      _ => fail("ordered fixture did not complete")
    }
  }
  fail("ordered fixture did not terminate")
}

///|
test "Unicode order metadata preserves NULL keys duplicates and authored winners" {
  let name = "x".repeat(128) + "😀é"
  let rows = "[{\"id\":4,\"" +
    name +
    "\":null},{\"id\":1,\"" +
    name +
    "\":7},{\"id\":3,\"" +
    name +
    "\":null},{\"id\":2,\"" +
    name +
    "\":7}]"
  for quantum in [1, 7, 256] {
    let distinct = indexed_snapshot_fixture(
      name,
      nullable=true,
      rows=Some(rows),
      operation=Some(
        order_metadata_operation("\"distinct\":[\"" + name + "\"]"),
      ),
    )
    let projected = finish_order_metadata_fixture(distinct, quantum)
    assert_eq(
      (completed_row_count(projected), completed_column_count(projected)),
      (2, 1),
    )
    assert_true(completed_cell(projected, 0, 0) is Some(Null))
    assert_true(completed_cell(projected, 1, 0) is Some(Number(7)))
    cleanup_bounded_binding_rows(distinct).unwrap() |> ignore
    assert_eq(distinct.state.workspace.live, 0)

    for
      (body, ids) in [
        (
          "\"sort\":[{\"field\":\"" +
          name +
          "\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"id\":\"desc\"}]",
          [4.0, 3.0, 2.0, 1.0],
        ),
        (
          "\"dedupe_rows\":{\"by\":[\"" +
          name +
          "\"],\"order_by\":[{\"id\":\"desc\"}]}",
          [4.0, 2.0],
        ),
      ] {
      let execution = indexed_snapshot_fixture(
        name,
        nullable=true,
        rows=Some(rows),
        keyed=true,
        operation=Some(order_metadata_operation(body)),
      )
      let output = finish_order_metadata_fixture(execution, quantum)
      assert_eq(completed_row_count(output), ids.length())
      for row, id in ids {
        assert_true(
          completed_cell(output, row, 0) is Some(Number(actual)) && actual == id,
        )
        if id >= 3 {
          assert_true(completed_cell(output, row, 1) is Some(Null))
        } else {
          assert_true(completed_cell(output, row, 1) is Some(Number(7)))
        }
      }
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
test "ordered metadata completes empty input without skipping metadata admission" {
  let name = "x".repeat(256)
  for
    body in [
      "\"sort\":[{\"" + name + "\":\"asc\"}]",
      "\"take\":{\"count\":1}",
      "\"distinct\":[\"" + name + "\"]",
    ] {
    for quantum in [1, 7, 256] {
      let execution = indexed_snapshot_fixture(
        name,
        rows=Some("[]"),
        operation=Some(order_metadata_operation(body)),
      )
      let output = finish_order_metadata_fixture(execution, quantum)
      assert_eq(completed_row_count(output), 0)
      assert_true(execution.state.control.remaining < 100000)
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
test "long order metadata stops inside name charges and key lookups without refund" {
  let name = "x".repeat(256)
  for
    (body, target) in [
      ("\"sort\":[{\"" + name + "\":\"asc\"}]", 0),
      ("\"take\":{\"count\":1}", 1),
      ("\"sort\":[{\"" + name + "\":\"asc\"}]", 2),
      ("\"assert_rows\":{\"unique_by\":[\"" + name + "\"]}", 3),
      (
        "\"dedupe_rows\":{\"by\":[\"" +
        name +
        "\"],\"order_by\":[{\"id\":\"desc\"}]}",
        4,
      ),
    ] {
    let execution = indexed_snapshot_fixture(
      name,
      operation=Some(order_metadata_operation(body)),
    )
    let mut reached = false
    for _ in 0..<5000 {
      if !reached {
        assert_true(
          advance_bounded_binding_rows(execution, 1).unwrap()
          is BoundedBindingRowsContinue(..),
        )
        reached = match execution.state.phase {
          ChargeSortNames =>
            target == 0 &&
            execution.state.name_charge
            .map(c => c.offset == 64)
            .unwrap_or(false)
          ChargeTakeNames =>
            target == 1 &&
            execution.state.name_charge
            .map(c => c.offset == 64)
            .unwrap_or(false)
          PrepareSortTerms =>
            target == 2 &&
            execution.state.metadata_lookup
            .map(c => c.offset == 64)
            .unwrap_or(false)
          CheckUniqueKeys =>
            target == 3 &&
            execution.state.name_charge
            .map(c => c.offset == 64)
            .unwrap_or(false)
          PrepareDedupeTerms =>
            target == 4 &&
            execution.state.metadata_lookup
            .map(c => c.offset == 64)
            .unwrap_or(false)
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
    assert_eq(execution.state.control.remaining, remaining)
    assert_eq(execution.state.workspace.live, 0)
    assert_true(execution.state.name_charge is None)
    assert_true(execution.state.metadata_lookup is None)
    assert_true(execution.state.term_column is None)
    assert_true((execution.state.available)())
  }
}
