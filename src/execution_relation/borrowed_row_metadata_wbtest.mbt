///|
fn borrowed_many_bindings_fixture() -> BoundedBindingRowsExecution raise {
  let members = Array::makei(64, index => {
    "\"b" + index.to_string() + "\":{\"literal\":" + index.to_string() + "}"
  }).join(",")
  indexed_snapshot_fixture(
    "x".repeat(128) + "😀",
    binding=true,
    operation=Some(order_metadata_operation("\"derive\":{" + members + "}")),
  )
}

///|
test "borrowed lowered projections preserve long rename and drop consumers" {
  let name = "x".repeat(128) + "😀"
  for quantum in [1, 7, 256] {
    for drop in [false, true] {
      let operation = if drop {
        "\"drop\":[\"" + name + "\"]"
      } else {
        "\"rename\":{\"" + name + "\":\"value\"}"
      }
      let execution = indexed_snapshot_fixture(
        name,
        operation=Some(order_metadata_operation(operation)),
      )
      assert_true(execution.state.metadata_projection is Some(_))
      let output = finish_order_metadata_fixture(execution, quantum)
      assert_eq(completed_column_count(output), if drop { 1 } else { 2 })
      assert_eq(completed_column_name(output, 0), Some("id"))
      assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
      if !drop {
        assert_eq(completed_column_name(output, 1), Some("value"))
        assert_true(completed_cell(output, 0, 1) is Some(Number(7.0)))
      }
      assert_true(cleanup_bounded_binding_rows(execution).unwrap())
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
test "borrowed bindings retain canonical values across resume quanta" {
  for quantum in [1, 7, 256] {
    let execution = borrowed_many_bindings_fixture()
    let view = execution.state.bindings.unwrap()
    assert_eq(@lower.bindings_count(view), 64)
    assert_false(@lower.bindings_ordered(view))
    assert_true(execution.state.output_names.is_empty())
    assert_true(execution.state.binding_execution is None)
    let output = finish_order_metadata_fixture(execution, quantum)
    assert_eq(completed_row_count(output), 1)
    for index in 0..<64 {
      let mut found = false
      for column, name in execution.state.output_names {
        if name == "b" + index.to_string() {
          assert_true(
            completed_cell(output, 0, column) is Some(Number(actual)) &&
            actual == index.to_double(),
          )
          found = true
        }
      }
      assert_true(found)
    }
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}

///|
test "borrowed ordered bindings preserve prior slots and shadow winners" {
  for quantum in [1, 7, 256] {
    let execution = indexed_snapshot_fixture(
      "x".repeat(128),
      binding=true,
      ordered_binding=true,
      operation=Some(
        order_metadata_operation(
          "\"derive\":[{\"z\":\"id + 1\"},{\"id\":\"z + 1\"},{\"a\":\"id + 1\"}]",
        ),
      ),
    )
    assert_true(@lower.bindings_ordered(execution.state.bindings.unwrap()))
    let output = finish_order_metadata_fixture(execution, quantum)
    for (name, expected) in [("a", 4.0), ("id", 3.0), ("z", 2.0)] {
      let mut found = false
      for column, actual_name in execution.state.output_names {
        if actual_name == name {
          assert_true(
            completed_cell(output, 0, column) is Some(Number(actual)) &&
            actual == expected,
          )
          found = true
        }
      }
      assert_true(found)
    }
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}

///|
test "borrowed binding cancellation retains input and reclaims active roots once" {
  let execution = borrowed_many_bindings_fixture()
  let mut entered = false
  for _ in 0..<30000 {
    if !entered {
      if execution.state.binding_execution is Some(child) &&
        child.slot > 0 &&
        child.active is Some(_) {
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
  let logical = execution.state.scope.unwrap().budget
  let spent = logical.work
  let held = execution.state.workspace.live
  assert_true(spent > 0L && held > 0)
  assert_true(@bounded.request_cancel(execution.state.engine))
  assert_true((execution.state.available)())
  assert_eq(execution.state.workspace.live, held)
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_false(execution.state.accepted.val)
  assert_eq(logical.work, spent)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq((execution.state.workspace.live, logical.live), (0, 0L))
  assert_true((execution.state.available)())
}
