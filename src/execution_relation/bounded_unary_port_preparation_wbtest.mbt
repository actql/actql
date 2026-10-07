///|
priv enum UnaryPortKernel {
  UnaryGroup(BoundedGroupExecution)
  UnaryCount(BoundedGlobalCountExecution)
  UnaryWindow(BoundedRowWindowExecution)
  UnaryUnpivot(BoundedUnpivotExecution)
  UnaryUnnest(BoundedUnnestExecution)
}

///|
priv enum UnaryPortPoll {
  UnaryContinue(Int64)
  UnaryComplete(CompletedOutput, Int64)
  UnaryNameLimit(Int64)
  UnaryStopped(Int64)
  UnaryUnexpected
}

///|
/// Each input is produced by the real checker and lowerer. Completion
/// preparation is never replaced with manually assembled internal state.
fn unary_port_fixture(
  kind : Int,
  name_bytes : Int,
) -> (@bounded.Control, UnaryPortKernel, CompletedOutput) raise {
  match kind {
    0 => {
      let (control, started, source) = bounded_relation_start(
        "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"k\":1}]",
        "\"group\":{\"by\":[\"k\"],\"aggregates\":{\"m\":{\"fn\":\"max\",\"field\":\"k\"}}}",
        "group_0",
        false,
        name_bytes~,
      )
      (control, UnaryGroup(started.unwrap()), source)
    }
    1 => {
      let (control, active, source) = bounded_global_count_fixture(
        "[{\"id\":null},{\"id\":1}]",
        max_work=10000,
        name_bytes~,
      )
      (control, UnaryCount(active), source)
    }
    2 => {
      let (control, active, source) = bounded_row_window_fixture(
        "[{\"at\":5,\"id\":1}]",
        name_bytes~,
      )
      (control, UnaryWindow(active), source)
    }
    3 => {
      let (control, active, source) = bounded_unpivot_fixture(
        "[{\"id\":1,\"jan\":10,\"feb\":null}]",
        name_bytes~,
      )
      (control, UnaryUnpivot(active), source)
    }
    4 => {
      let (control, active, source) = bounded_unnest_fixture(
        "[{\"id\":1,\"items\":[2,null]}]",
        name_bytes~,
      )
      (control, UnaryUnnest(active), source)
    }
    5 => {
      let (control, started, source) = bounded_relation_start(
        bounded_analytic_schema,
        "[{\"id\":1,\"amount\":null}]",
        bounded_analytic_operation,
        "analytic_0",
        false,
        name_bytes~,
      )
      (control, UnaryGroup(started.unwrap()), source)
    }
    6 => {
      let (control, started, source) = bounded_relation_start(
        bounded_pivot_schema,
        "[{\"id\":1,\"status\":\"open\",\"amount\":5}]",
        bounded_pivot_max,
        "pivot_0",
        false,
        name_bytes~,
      )
      (control, UnaryGroup(started.unwrap()), source)
    }
    _ => fail("unknown unary port fixture")
  }
}

///|
fn unary_port_advance(active : UnaryPortKernel, quantum : Int) -> UnaryPortPoll {
  match active {
    UnaryGroup(value) =>
      match advance_bounded_group_execution(value, quantum).unwrap() {
        BoundedGroupContinue(work~, ..) => UnaryContinue(work)
        BoundedGroupComplete(output, work~, ..) => UnaryComplete(output, work)
        BoundedGroupFailed(Completion(Limit), work~, ..) => UnaryNameLimit(work)
        BoundedGroupStopped(_, work~, ..) => UnaryStopped(work)
        _ => UnaryUnexpected
      }
    UnaryCount(value) =>
      match advance_bounded_global_count(value, quantum).unwrap() {
        BoundedGlobalCountContinue(work~, ..) => UnaryContinue(work)
        BoundedGlobalCountComplete(output, work~, ..) =>
          UnaryComplete(output, work)
        BoundedGlobalCountFailed(Completion(Limit), work~, ..) =>
          UnaryNameLimit(work)
        BoundedGlobalCountStopped(_, work~, ..) => UnaryStopped(work)
        _ => UnaryUnexpected
      }
    UnaryWindow(value) =>
      match advance_bounded_row_window(value, quantum).unwrap() {
        BoundedRowWindowContinue(work~, ..) => UnaryContinue(work)
        BoundedRowWindowComplete(output, work~, ..) =>
          UnaryComplete(output, work)
        BoundedRowWindowFailed(Completion(Limit), work~, ..) =>
          UnaryNameLimit(work)
        BoundedRowWindowStopped(_, work~, ..) => UnaryStopped(work)
        _ => UnaryUnexpected
      }
    UnaryUnpivot(value) =>
      match advance_bounded_unpivot(value, quantum).unwrap() {
        BoundedUnpivotContinue(work~, ..) => UnaryContinue(work)
        BoundedUnpivotComplete(output, work~, ..) => UnaryComplete(output, work)
        BoundedUnpivotFailed(Completion(Limit), work~, ..) =>
          UnaryNameLimit(work)
        BoundedUnpivotStopped(_, work~, ..) => UnaryStopped(work)
        _ => UnaryUnexpected
      }
    UnaryUnnest(value) =>
      match advance_bounded_unnest(value, quantum).unwrap() {
        BoundedUnnestContinue(work~, ..) => UnaryContinue(work)
        BoundedUnnestComplete(output, work~, ..) => UnaryComplete(output, work)
        BoundedUnnestFailed(Completion(Limit), work~, ..) =>
          UnaryNameLimit(work)
        BoundedUnnestStopped(_, work~, ..) => UnaryStopped(work)
        _ => UnaryUnexpected
      }
  }
}

///|
fn unary_port_cursor(active : UnaryPortKernel) -> TrustedOutputPreparation? {
  match active {
    UnaryGroup(value) => value.state.port_preparation
    UnaryCount(value) => value.state.port_preparation
    UnaryWindow(value) => value.state.port_preparation
    UnaryUnpivot(value) => value.state.port_preparation
    UnaryUnnest(value) => value.state.port_preparation
  }
}

///|
fn unary_port_totals(active : UnaryPortKernel) -> (Int, Int) {
  match active {
    UnaryGroup(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    UnaryCount(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    UnaryWindow(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    UnaryUnpivot(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    UnaryUnnest(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
  }
}

///|
fn unary_port_unpublished(active : UnaryPortKernel) -> Bool {
  match active {
    UnaryGroup(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    UnaryCount(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    UnaryWindow(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    UnaryUnpivot(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    UnaryUnnest(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
  }
}

///|
fn unary_port_cleanup(active : UnaryPortKernel) -> Bool {
  match active {
    UnaryGroup(value) =>
      cleanup_bounded_group_execution(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None &&
      value.state.evaluation is None
    UnaryCount(value) =>
      cleanup_bounded_global_count(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    UnaryWindow(value) =>
      cleanup_bounded_row_window(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    UnaryUnpivot(value) =>
      cleanup_bounded_unpivot(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    UnaryUnnest(value) =>
      cleanup_bounded_unnest(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
  }
}

///|
fn unary_port_names(kind : Int) -> Array[String] {
  match kind {
    0 => ["k", "m"]
    1 => ["n", "present"]
    2 => ["at", "id", "window_end", "window_start"]
    3 => ["amount", "id", "jan", "metric"]
    4 => ["id", "item", "items", "position"]
    5 => ["amount", "id", "n", "position"]
    6 => ["id", "open"]
    _ => []
  }
}

///|
fn unary_port_expected(kind : Int) -> Array[String] {
  match kind {
    0 => ["{\"k\":1,\"m\":1}"]
    1 => ["{\"n\":2,\"present\":1}"]
    2 =>
      [
        "{\"at\":5,\"id\":1,\"window_end\":6,\"window_start\":-4}", "{\"at\":5,\"id\":1,\"window_end\":12,\"window_start\":2}",
      ]
    3 =>
      [
        "{\"amount\":10,\"id\":1,\"jan\":10,\"metric\":\"jan\"}", "{\"amount\":null,\"id\":1,\"jan\":10,\"metric\":\"feb\"}",
        "{\"amount\":10,\"id\":1,\"jan\":10,\"metric\":\"jan\"}",
      ]
    4 =>
      [
        "{\"id\":1,\"item\":2,\"items\":[2,null],\"position\":0}", "{\"id\":1,\"item\":null,\"items\":[2,null],\"position\":1}",
      ]
    5 => ["{\"amount\":null,\"id\":1,\"n\":0,\"position\":1}"]
    6 => ["{\"id\":1,\"open\":5}"]
    _ => []
  }
}

///|
/// Each literal ASCII target occurs twice; each schema name occurs once.
/// These byte expectations are not measured from a successful execution.
fn unary_port_exact_bytes(kind : Int) -> Int {
  match kind {
    0 => 2 * 7 + 1 + 1
    1 => 2 * 7 + 1 + 7
    2 => 2 * 8 + 2 + 2 + 10 + 12
    3 => 2 * 9 + 6 + 2 + 3 + 6
    4 => 2 * 8 + 2 + 4 + 5 + 8
    5 => 2 * 10 + 6 + 2 + 1 + 8
    6 => 2 * 7 + 2 + 4
    _ => -1
  }
}

///|
fn check_unary_port_boundary(kind : Int) -> Unit raise {
  let mut baseline : (Int64, (Int, Int))? = None
  for quantum in [1, 7, 256] {
    for short in [false, true] {
      let (_, active, source) = unary_port_fixture(
        kind,
        unary_port_exact_bytes(kind) - (if short { 1 } else { 0 }),
      )
      assert_true(unary_port_cursor(active) is Some(_))
      assert_true(unary_port_unpublished(active))
      let mut terminal = false
      let mut previous = 0L
      for _ in 0..<3000 {
        if !terminal {
          match unary_port_advance(active, quantum) {
            UnaryContinue(work) => {
              assert_true(
                work > previous && work - previous <= quantum.to_int64(),
              )
              previous = work
            }
            UnaryComplete(output, work) => {
              assert_false(short)
              assert_true(work - previous <= quantum.to_int64())
              assert_eq(
                completed_column_count(output),
                unary_port_names(kind).length(),
              )
              for column, name in unary_port_names(kind) {
                assert_eq(completed_column_name(output, column), Some(name))
              }
              let actual = Array::makei(completed_row_count(output), row => {
                completed_output_row_wire(output, row, 1000, 100, 20).unwrap()
              })
              assert_eq(actual, unary_port_expected(kind))
              let totals = (work, unary_port_totals(active))
              if baseline is Some(expected) {
                assert_eq(totals, expected)
              } else {
                baseline = Some(totals)
              }
              assert_true(unary_port_cleanup(active))
              assert_false(unary_port_cleanup(active))
              assert_true(completed_output_available(output))
              for column, name in unary_port_names(kind) {
                assert_eq(completed_column_name(output, column), Some(name))
              }
              terminal = true
            }
            UnaryNameLimit(work) => {
              assert_true(short)
              assert_true(work - previous <= quantum.to_int64())
              assert_true(unary_port_unpublished(active))
              assert_true(unary_port_cleanup(active))
              assert_false(unary_port_cleanup(active))
              terminal = true
            }
            _ => fail("unexpected unary completion outcome")
          }
        }
      }
      assert_true(terminal)
      assert_true(completed_output_available(source))
    }
  }
}

///|
test "bounded unary group completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(0)
}

///|
test "bounded unary count completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(1)
}

///|
test "bounded unary window completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(2)
}

///|
test "bounded unary unpivot completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(3)
}

///|
test "bounded unary unnest completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(4)
}

///|
test "bounded unary analytic completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(5)
}

///|
test "bounded unary pivot completion preparation has exact bytes and quantum-independent work" {
  check_unary_port_boundary(6)
}

///|
test "bounded unary completion preparation cancels inside every name phase" {
  for kind in 0..<7 {
    for phase in 0..<4 {
      let (control, active, source) = unary_port_fixture(
        kind,
        unary_port_exact_bytes(kind),
      )
      let mut reached = false
      for _ in 0..<200 {
        if !reached {
          let cursor = unary_port_cursor(active).unwrap()
          if cursor.phase == phase && cursor.offset > 0 {
            reached = true
          } else {
            assert_true(unary_port_advance(active, 1) is UnaryContinue(_))
          }
        }
      }
      assert_true(reached)
      assert_true(unary_port_unpublished(active))
      let held_cursor = unary_port_cursor(active).unwrap()
      let totals = unary_port_totals(active)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        unary_port_advance(active, 1) is UnaryStopped(work) && work > 0L,
      )
      assert_true(unary_port_unpublished(active))
      assert_true(completed_output_available(source))
      assert_true(unary_port_cleanup(active))
      assert_false(unary_port_cleanup(active))
      assert_true(held_cursor.closed)
      assert_eq(held_cursor.names.length(), 0)
      assert_eq(unary_port_totals(active), totals)
      assert_true(completed_output_available(source))
    }
  }
}

///|
fn unary_unicode_group(
  name_bytes : Int,
) -> (@bounded.Control, BoundedGroupExecution, CompletedOutput, String) raise {
  // U+00E9 uses two UTF-8 bytes, U+1F600 uses four. Neither value content
  // nor the schema spelling is normalized by completion preparation.
  let name = "é😀".repeat(32)
  let (control, started, source) = bounded_relation_start(
    "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"k\":1}]",
    "\"group\":{\"by\":[\"k\"],\"aggregates\":{\"" +
    name +
    "\":{\"fn\":\"max\",\"field\":\"k\"}}}",
    "group_0",
    false,
    max_work=10000,
    name_bytes~,
  )
  (control, started.unwrap(), source, name)
}

///|
test "bounded unary completion preparation retains long Unicode names across quanta" {
  let exact_bytes = 2 * 7 + 1 + 32 * (2 + 4)
  let mut baseline : (Int64, Int)? = None
  for quantum in [1, 7, 256] {
    for short in [false, true] {
      let (_, value, source, name) = unary_unicode_group(
        exact_bytes - (if short { 1 } else { 0 }),
      )
      assert_true(value.state.port is None)
      let mut terminal = false
      let mut previous = 0L
      for _ in 0..<3000 {
        if !terminal {
          match unary_port_advance(UnaryGroup(value), quantum) {
            UnaryContinue(work) => {
              assert_true(
                work > previous && work - previous <= quantum.to_int64(),
              )
              previous = work
            }
            UnaryComplete(output, work) => {
              assert_false(short)
              assert_true(work - previous <= quantum.to_int64())
              assert_eq(completed_column_count(output), 2)
              assert_eq(completed_column_name(output, 0), Some("k"))
              assert_eq(completed_column_name(output, 1), Some(name))
              assert_eq(completed_row_count(output), 1)
              assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
              assert_true(completed_cell(output, 0, 1) is Some(Number(1)))
              let totals = (work, value.state.control.remaining)
              if baseline is Some(expected) {
                assert_eq(totals, expected)
              } else {
                baseline = Some(totals)
              }
              assert_true(unary_port_cleanup(UnaryGroup(value)))
              assert_true(completed_output_available(output))
              assert_eq(completed_column_name(output, 1), Some(name))
              terminal = true
            }
            UnaryNameLimit(work) => {
              assert_true(short)
              assert_true(work - previous <= quantum.to_int64())
              assert_true(unary_port_unpublished(UnaryGroup(value)))
              assert_true(unary_port_cleanup(UnaryGroup(value)))
              terminal = true
            }
            _ => fail("unexpected Unicode completion outcome")
          }
        }
      }
      assert_true(terminal)
      assert_true(completed_output_available(source))
    }
  }
}

///|
test "bounded unary completion preparation cancels inside a long Unicode name" {
  let (control, value, source, _) = unary_unicode_group(2 * 7 + 1 + 32 * 6)
  let mut reached = false
  for _ in 0..<300 {
    if !reached {
      let cursor = value.state.port_preparation.unwrap()
      if cursor.phase == 3 && cursor.column == 1 && cursor.offset >= 48 {
        reached = true
      } else {
        assert_true(
          unary_port_advance(UnaryGroup(value), 1) is UnaryContinue(_),
        )
      }
    }
  }
  assert_true(reached)
  let cursor = value.state.port_preparation.unwrap()
  assert_eq(cursor.names, ["k"])
  assert_true(@bounded.request_cancel(control))
  assert_true(
    unary_port_advance(UnaryGroup(value), 1) is UnaryStopped(work) && work > 0L,
  )
  assert_true(unary_port_unpublished(UnaryGroup(value)))
  assert_true(unary_port_cleanup(UnaryGroup(value)))
  assert_false(unary_port_cleanup(UnaryGroup(value)))
  assert_true(cursor.closed)
  assert_eq(cursor.names.length(), 0)
  assert_true(completed_output_available(source))
}
