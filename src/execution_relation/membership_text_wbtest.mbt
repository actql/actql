///|
fn long_text_membership(
  left : String,
  items : String,
  op? : String = "in",
) -> @lower.Expression {
  membership_lowered(
    "{\"type\":\"string\",\"nullable\":true}",
    "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"string\",\"nullable\":true}}",
    left,
    items,
    op~,
  )
}

///|
test "bounded filter stops during the second long membership comparison" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"tag\":\"" + String::make(256, 'g') + "\"}]",
    membership_text=true,
    fragment_rows=1L,
  )
  let logical = execution.state.logical.unwrap()
  let mut reached = false
  for _ in 0..<6000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(_, ..) =>
        fail("filter failed before pending membership")
      _ => fail("filter completed before pending membership")
    }
    if execution.state.predicate_execution is Some(frame) &&
      frame.state is CompareMembership(state, comparison) &&
      state.index == 1 &&
      state.matched &&
      comparison.phase == 2 &&
      comparison.offset > 64 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let consumed = logical.work
  let held = execution.state.workspace.live
  assert_true(held > 0)
  assert_false(execution.state.input_roots[0].root.released)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq((logical.work, execution.state.workspace.live), (consumed, held))
  assert_false(execution.state.input_roots[0].root.released)
  assert_true(execution.state.rows.val is None)
  assert_false(execution.accepted.val)
  assert_true(producer_read_available(input))
  for attempt in 0..<2 {
    assert_eq(cleanup_bounded_binding_rows(execution).unwrap(), attempt == 0)
    assert_eq(
      (logical.work, logical.live, execution.state.workspace.live),
      (consumed, 0L, 0),
    )
    assert_true(producer_read_available(input))
  }
}

///|
test "membership Text comparison exposes equal prefix and byte charging" {
  let text = String::make(4096, 'g')
  let control = { remaining: 10000, max_frames: 10, }
  let workspace = row_workspace(10)
  let frame = expression_frame(
    long_text_membership("\"" + text + "\"", "[\"" + text + "\"]"),
    {},
    [],
    control,
    workspace,
    None,
  ).unwrap()
  let mut result : EvaluatedValue? = None
  let mut polls = 0
  for _ in 0..<15000 {
    let before = control.remaining
    result = advance_expression_frame(frame).unwrap()
    assert_true(before - control.remaining <= 64)
    polls += 1
    if result is Some(_) {
      break
    }
  }
  guard result is Some(result) else { fail("membership did not terminate") }
  membership_assert(result.value, Some(true))
  assert_true(polls > 12000)
  // Six semantic transitions and two membership transitions (one item,
  // one end), plus both 4096-byte operands. Parameters are already bound.
  assert_eq(control.remaining, 10000 - 8192 - 8)
  assert_eq(workspace.live, 0)
}

///|
test "long membership keeps exact control workspace and three valued results" {
  let prefix = String::make(80, 'g')
  for
    (left, items, expected) in [
      ("\"" + prefix + "\"", "[\"" + prefix + "\"]", Some(true)),
      ("\"" + prefix + "\"", "[\"" + prefix + "x\",null]", None),
      ("\"" + prefix + "\"", "[null,\"" + prefix + "\"]", Some(true)),
      ("null", "[\"" + prefix + "\"]", None),
      ("\"" + prefix + "\"", "[]", Some(false)),
      ("\"" + prefix + "\"", "null", Some(false)),
      ("\"" + prefix + "😀\"", "[\"" + prefix + "\ue000\"]", Some(false)),
      ("\"" + prefix + "😀\"", "[\"" + prefix + "😀\"]", Some(true)),
    ] {
    for op in ["in", "not_in"] {
      for drain in [false, true] {
        let workspace = row_workspace(3)
        let frame = expression_frame(
          long_text_membership(left, items, op~),
          {},
          [],
          { remaining: 1000, max_frames: 10, },
          workspace,
          None,
        ).unwrap()
        let mut result : EvaluatedValue? = None
        for _ in 0..<2000 {
          result = advance_expression_frame(frame, drain~).unwrap()
          if result is Some(_) {
            break
          }
        }
        guard result is Some(result) else {
          fail("membership did not terminate")
        }
        membership_assert(
          result.value,
          expected.map(x => if op == "not_in" { !x } else { x }),
        )
        assert_eq(workspace.live, 0)
      }
    }
  }
  let text = "\"" + String::make(256, 'g') + "\""
  // Six expression transitions plus two item/end transitions and 512 UTF-8
  // bytes. One membership handle plus the two shared comparison handles.
  for (work, slots, failure) in [(520, 3, 0), (519, 3, 1), (520, 2, 2)] {
    for drain in [false, true] {
      let budget = { remaining: work, max_frames: 10, }
      let workspace = row_workspace(slots)
      let frame = expression_frame(
        long_text_membership(text, "[" + text + "]"),
        {},
        [],
        budget,
        workspace,
        None,
      ).unwrap()
      let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
      for _ in 0..<2000 {
        result = advance_expression_frame(frame, drain~)
        if !(result is Ok(None)) {
          break
        }
      }
      match failure {
        0 => {
          guard result is Ok(Some(value)) else {
            fail("exact membership control")
          }
          membership_assert(value.value, Some(true))
          assert_eq((budget.remaining, workspace.peak), (0, 3))
        }
        1 => assert_true(result is Err({ kind: ControlLimit, .. }))
        2 => assert_true(result is Err({ kind: WorkspaceLimit, .. }))
        _ => fail("unknown membership boundary")
      }
      assert_eq(workspace.live, 0)
    }
  }
}

///|
test "long membership preserves logical work across matches and resume quanta" {
  let text = String::make(256, 'g')
  for
    (items, expected) in [
      ("[\"" + text + "\",\"" + text + "\"]", true),
      ("[\"" + text + "\",\"" + String::make(256, 'h') + "\"]", true),
      ("[\"" + String::make(256, 'h') + "\",\"" + text + "\"]", true),
      (
        "[\"" +
        String::make(256, 'h') +
        "\",\"" +
        String::make(256, 'h') +
        "\"]",
        false,
      ),
    ] {
    // Three entries, left weight 257 and list weight 515, each produced and
    // consumed once, then Boolean weight 1: 3 + 2*(257+515) + 1 = 1548.
    // The 258-byte left and 519-byte list coexist: peak 777 bytes.
    for
      (work, live, failure) in [
        (1548L, 777L, 0),
        (1547L, 777L, 1),
        (1548L, 776L, 2),
      ] {
      for quantum in [1, 7] {
        let logical = text_expression_budget(work, live)
        let frame = expression_frame(
          long_text_membership("\"" + text + "\"", items),
          {},
          [],
          { remaining: 10000, max_frames: 10, },
          row_workspace(100),
          Some(expression_roots(logical, 10)),
        ).unwrap()
        let mut result : Result[EvaluatedValue?, EvalIssue] = Ok(None)
        for _ in 0..<3000 {
          for _ in 0..<quantum {
            result = advance_expression_frame(frame)
            if !(result is Ok(None)) {
              break
            }
          }
          if !(result is Ok(None)) {
            break
          }
        }
        match failure {
          0 => {
            guard result is Ok(Some(value)) else {
              fail("exact logical membership")
            }
            membership_assert(value.value, Some(expected))
            assert_eq((logical.work, logical.peak), (1548L, 777L))
            release_logical_root(logical, value.root.unwrap()).unwrap()
          }
          1 =>
            assert_true(
              result
              is Err({ kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }),
            )
          2 =>
            assert_true(
              result is Err({ kind: LogicalValue(LiveValueLimit), .. }),
            )
          _ => fail("unknown logical membership boundary")
        }
        close_expression_frame(frame)
        assert_eq((logical.live, frame.workspace.live), (0L, 0))
      }
    }
  }
}

///|
test "long membership cancellation in every comparison phase preserves custody" {
  let text = "\"" + String::make(256, 'g') + "\""
  for phase in 0..<3 {
    let logical = text_expression_budget(10000L, 10000L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let frame = expression_frame(
      long_text_membership(text, "[" + text + "," + text + "]"),
      {},
      [],
      { remaining: 10000, max_frames: 10, },
      row_workspace(100),
      Some(expression_roots(logical, 10)),
    ).unwrap()
    let mut found = false
    for _ in 0..<3000 {
      assert_true(advance_expression_frame(frame).unwrap() is None)
      if frame.state is CompareMembership(state, comparison) &&
        state.index == 1 &&
        comparison.phase == phase &&
        (phase < 2 || comparison.offset > 0) {
        assert_true(state.matched)
        found = true
        break
      }
    }
    assert_true(found)
    let work = logical.work
    close_expression_frame(frame)
    close_expression_frame(frame)
    assert_eq(logical.work, work)
    assert_eq((logical.live, frame.workspace.live), (1L, 0))
    assert_false(borrowed.released)
    release_logical_root(logical, borrowed).unwrap()
  }
}
