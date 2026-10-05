///|
/// Every cell of a completed output, in row order, for content comparison.
fn bounded_output_cells(output : CompletedOutput) -> Array[String] {
  let cells = []
  for row in 0..<completed_row_count(output) {
    for column in 0..<completed_column_count(output) {
      cells.push(
        match completed_cell(output, row, column) {
          Some(value) => group_step_cell(value)
          None => "missing"
        },
      )
    }
  }
  cells
}

///|
/// One bounded group-family execution with a fixed input and its measured
/// peak of admitted workspace entries.
priv struct GroupWorkspaceCase {
  label : String
  schema : String
  rows : String
  operation : String
  retained : String
  peak : Int
}

///|
fn run_group_workspace(
  case : GroupWorkspaceCase,
  entries : Int,
) -> Array[String]? raise {
  let (_, started, source) = bounded_relation_start(
    case.schema,
    case.rows,
    case.operation,
    case.retained,
    false,
    max_entries=entries,
  )
  // Only the workspace row limit counts as the expected rejection.
  let result = match started {
    Err(_) => fail(case.label + ": start rejected before execution")
    Ok(execution) => {
      let cells = match drive_bounded_group(execution) {
        BoundedGroupComplete(output, ..) => Some(bounded_output_cells(output))
        BoundedGroupFailed(Rows(RowLimit), ..) => None
        _ => fail(case.label + ": unexpected workspace outcome")
      }
      assert_true(cleanup_bounded_group_execution(execution).unwrap())
      cells
    }
  }
  assert_true(completed_output_available(source))
  result
}

///|
test "bounded group-family executions admit their exact workspace peak" {
  // Peaks are the admitted workspace entries of the fixed inputs: rows,
  // names, sort state and per-group or per-partition state of each kernel.
  let cases : Array[GroupWorkspaceCase] = [
    {
      label: "pivot",
      schema: bounded_pivot_schema,
      rows: "[{\"id\":2,\"status\":\"open\",\"amount\":5},{\"id\":1,\"status\":\"open\",\"amount\":7},{\"id\":2,\"status\":\"open\",\"amount\":9}]",
      operation: bounded_pivot_max,
      retained: "pivot_0",
      peak: 27,
    },
    {
      label: "analytic",
      schema: bounded_analytic_schema,
      rows: "[{\"id\":2,\"amount\":5},{\"id\":1,\"amount\":null},{\"id\":3,\"amount\":7}]",
      operation: bounded_analytic_operation,
      retained: "analytic_0",
      peak: 101,
    },
    {
      label: "general group",
      schema: "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
      rows: "[{\"k\":3},{\"k\":1},{\"k\":3},{\"k\":2}]",
      operation: "\"group\":{\"by\":[\"k\"],\"aggregates\":{\"m\":{\"fn\":\"max\",\"field\":\"k\"}}}",
      retained: "group_0",
      peak: 28,
    },
  ]
  for case in cases {
    let reference = run_group_workspace(case, 1000).unwrap()
    guard run_group_workspace(case, case.peak) is Some(exact) else {
      fail(case.label + ": exact workspace rejected")
    }
    assert_eq(exact, reference)
    assert_true(run_group_workspace(case, case.peak - 1) is None)
  }
}

///|
fn run_set_workspace(operation : String, entries : Int) -> Array[String]? raise {
  let (_, started, reads) = bounded_set_fixture(
    operation~,
    left_rows="[{\"id\":1},{\"id\":2},{\"id\":1}]",
    right_rows="[{\"id\":1},{\"id\":3}]",
    max_entries=entries,
    max_work=100000,
    max_rows=10,
  )
  let result = match started {
    Err(_) => fail(operation + ": start rejected before execution")
    Ok(execution) => {
      let ids = match drive_bounded_set(execution) {
        BoundedSetComplete(output, ..) => Some(bounded_set_ids(output))
        BoundedSetFailed(Rows(RowLimit), ..) => None
        _ => fail(operation + ": unexpected workspace outcome")
      }
      assert_true(cleanup_bounded_set(execution).unwrap())
      ids
    }
  }
  assert_true(reads.all(read => producer_read_available(read)))
  result
}

///|
test "bounded set operations admit their exact workspace peak" {
  // Three left and two right rows: per-side seed, sort and keep entries plus
  // the output row entries (22).
  for case in [("except", ["1", "2"]), ("intersect", ["1"])] {
    let (operation, expected) = case
    assert_eq(run_set_workspace(operation, 1000), Some(expected))
    assert_eq(run_set_workspace(operation, 22), Some(expected))
    assert_true(run_set_workspace(operation, 21) is None)
  }
}

///|
test "bounded intersect admits exact work and rejects one unit short" {
  // One matching left and right row: input admission, name resolution, both
  // sorts, one comparison, one keep flag and one output row (27).
  let exact_work = 27
  let (_, exact, _) = bounded_set_fixture(
    operation="intersect",
    left_rows="[{\"id\":1}]",
    right_rows="[{\"id\":1}]",
    max_work=exact_work,
  )
  let exact = exact.unwrap()
  match drive_bounded_set(exact) {
    BoundedSetComplete(output, ..) => assert_eq(bounded_set_ids(output), ["1"])
    _ => fail("exact intersect work rejected")
  }
  assert_true(cleanup_bounded_set(exact).unwrap())
  let (_, short, _) = bounded_set_fixture(
    operation="intersect",
    left_rows="[{\"id\":1}]",
    right_rows="[{\"id\":1}]",
    max_work=exact_work - 1,
  )
  let short = short.unwrap()
  match drive_bounded_set(short) {
    BoundedSetFailed(Rows(RowLimit), ..) => ()
    _ => fail("one-short intersect work accepted")
  }
  assert_true(cleanup_bounded_set(short).unwrap())
}

///|
test "bounded intersect stops after positive work without publishing" {
  let (control, started, reads) = bounded_set_fixture(
    operation="intersect",
    left_rows="[{\"id\":3},{\"id\":1},{\"id\":2}]",
    right_rows="[{\"id\":2}]",
  )
  let execution = started.unwrap()
  for _ in 0..<15 {
    assert_true(
      advance_bounded_set(execution, 1).unwrap() is BoundedSetContinue(..),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_set(execution, 1).unwrap() is BoundedSetStopped(_, ..),
  )
  assert_true(cleanup_bounded_set(execution).unwrap())
  assert_true(reads.all(read => producer_read_available(read)))
}

///|
fn run_nest_workspace(entries : Int) -> Array[Int]? raise {
  let (_, started, reads) = bounded_nest_fixture(
    left_rows="[{\"id\":1,\"key\":1},{\"id\":2,\"key\":1}]",
    right_rows="[{\"key\":1,\"value\":5},{\"key\":1,\"value\":6}]",
    max_entries=entries,
    max_work=100000,
  )
  let result = match started {
    Err(_) => fail("nest: start rejected before execution")
    Ok(execution) => {
      let counts = match drive_bounded_nest(execution) {
        BoundedNestComplete(output, ..) =>
          Some(bounded_nest_item_counts(output))
        BoundedNestFailed(Rows(RowLimit), ..) => None
        _ => fail("nest: unexpected workspace outcome")
      }
      assert_true(cleanup_bounded_nest(execution).unwrap())
      assert_true(bounded_nest_released(execution))
      counts
    }
  }
  assert_true(reads.all(read => producer_read_available(read)))
  result
}

///|
test "bounded nest admits its exact workspace peak" {
  // Two parents share one key and two children. Key/field metadata uses
  // 2 + 2 slots, three output metadata arrays use 3 * 3, and the child
  // index/sort/grouped arrays use 3 * 2: 19 persistent slots. Each parent
  // adds 2 matches, a three-cell row plus builder, and 2 projected items:
  // 2 * (2 + 3 + 1 + 2) = 16. During the second row's nested output scan,
  // the remaining array continuation overlaps one Object/Number frame.
  // These 2 traversal frames make the independently derived peak 37.
  assert_eq(run_nest_workspace(1000), Some([2, 2]))
  assert_eq(run_nest_workspace(37), Some([2, 2]))
  assert_true(run_nest_workspace(36) is None)
}
