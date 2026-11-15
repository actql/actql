///|
fn reach_join_input_text(execution : BoundedJoinExecution) -> Unit raise {
  for _ in 0..<10000 {
    if execution.state.phase is ChargeInput &&
      execution.state.input_scan.frames.last() is Some(ScanText(text, index)) &&
      text.length() - index > 256 {
      return
    }
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
    )
  }
  fail("input text cursor was not reached")
}

///|
fn join_input_text_row() -> String {
  "[{\"id\":\"" + "x".repeat(1024) + "\",\"v\":10}]"
}

///|
test "join text quantum retains current checks without per-code-unit probes" {
  let counts = []
  for quantum in [64, 256] {
    let calls = Ref(0)
    let (control, execution, _) = bounded_join_fixture(
      left_rows=join_input_text_row(),
      right_rows=join_input_text_row(),
      key_type="string",
      left_current=Some(() => {
        calls.val += 1
        true
      }),
    )
    reach_join_input_text(execution)
    calls.val = 0
    let before = execution.state.control.remaining
    let text_before = execution.state.input_scan.budget.text
    assert_true(
      advance_bounded_join(execution, quantum).unwrap()
      is BoundedJoinContinue(..),
    )
    assert_eq(before - execution.state.control.remaining, quantum)
    assert_eq(execution.state.input_scan.budget.text - text_before, quantum)
    assert_true(calls.val > 0)
    counts.push(calls.val)
    assert_true(execution.state.rows.val is None)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
    )
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
  }
  // More immutable text units retain the fences without multiplying probes.
  assert_eq(counts[0], counts[1])
}

///|
test "join text quantum cannot retain current across resume" {
  let live = Ref(true)
  let (_, execution, _) = bounded_join_fixture(
    left_rows=join_input_text_row(),
    right_rows=join_input_text_row(),
    key_type="string",
    left_current=Some(() => live.val),
  )
  reach_join_input_text(execution)
  assert_true(
    advance_bounded_join(execution, 128).unwrap() is BoundedJoinContinue(..),
  )
  live.val = false
  let before = execution.state.control.remaining
  assert_true(
    advance_bounded_join(execution, 128).unwrap()
    is BoundedJoinFailed(InvalidExecution, ..),
  )
  assert_eq(execution.state.control.remaining, before)
  assert_true(execution.state.rows.val is None)
  assert_true(cleanup_bounded_join(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "join text quantum refuses an external current callback at exit" {
  let armed = Ref(false)
  let calls = Ref(0)
  let (_, execution, _) = bounded_join_fixture(
    left_rows=join_input_text_row(),
    right_rows=join_input_text_row(),
    key_type="string",
    right_current=Some(() => {
      if armed.val {
        calls.val += 1
        calls.val < 2
      } else {
        true
      }
    }),
  )
  reach_join_input_text(execution)
  armed.val = true
  assert_true(
    advance_bounded_join(execution, 128).unwrap()
    is BoundedJoinFailed(InvalidExecution, ..),
  )
  assert_eq(calls.val, 2)
  assert_true(execution.state.rows.val is None)
  assert_true(cleanup_bounded_join(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "join text quantum checks cancellation after an entry callback" {
  let armed = Ref(false)
  let stop = Ref(None)
  let (control, execution, _) = bounded_join_fixture(
    left_rows=join_input_text_row(),
    right_rows=join_input_text_row(),
    key_type="string",
    right_current=Some(() => {
      if armed.val {
        stop.val.map(control => @bounded.request_cancel(control)) |> ignore
      }
      true
    }),
  )
  stop.val = Some(control)
  reach_join_input_text(execution)
  armed.val = true
  let before = execution.state.control.remaining
  assert_true(
    advance_bounded_join(execution, 128).unwrap()
    is BoundedJoinStopped(@bounded.Cancelled, ..),
  )
  assert_eq(before - execution.state.control.remaining, 1)
  assert_true(execution.state.rows.val is None)
  assert_true(cleanup_bounded_join(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "input text keeps its owned slot and exact Unicode charges" {
  let reserves = Ref(0)
  let (control, execution, _) = bounded_join_fixture(
    left_rows=join_input_text_row(),
    right_rows=join_input_text_row(),
    key_type="string",
    reserve=Some(_ => {
      reserves.val += 1
      Ok(())
    }),
  )
  reach_join_input_text(execution)
  let scan = execution.state.input_scan
  let last = scan.frames.length() - 1
  scan.frames[last] = ScanText("aé😀", 0)
  let live = scan.workspace.live
  let peak = scan.workspace.peak
  let callbacks = reserves.val
  let text = scan.budget.text
  let work = scan.control.remaining
  for _ in 0..<3 {
    assert_true(advance_binary_input_scan(scan) is Ok(false))
  }
  assert_eq(scan.budget.text - text, 7)
  assert_eq(work - scan.control.remaining, 3)
  assert_eq(scan.workspace.live, live - 1)
  assert_eq(scan.workspace.peak, peak)
  assert_eq(reserves.val, callbacks)
  assert_eq(scan.frames.length(), last)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
  )
  assert_true(cleanup_bounded_join(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "input text rejects malformed UTF16 and byte exhaustion without leaking its slot" {
  for units in [[0xd800], [0xdc00], [0xd800, 0x61], [0x61]] {
    let (control, execution, _) = bounded_join_fixture(
      left_rows=join_input_text_row(),
      right_rows=join_input_text_row(),
      key_type="string",
    )
    reach_join_input_text(execution)
    let scan = execution.state.input_scan
    let last = scan.frames.length() - 1
    let text = String::from_array(units.map(unit => unit.unsafe_to_char()))
    scan.frames[last] = ScanText(text, 0)
    if units is [0x61] {
      scan.budget.text = scan.budget.limits.max_text_bytes
    }
    let bytes = scan.budget.text
    let live = scan.workspace.live
    assert_true(advance_binary_input_scan(scan) is Err(ValueLimit))
    assert_eq(scan.budget.text, bytes)
    assert_eq(scan.frames.length(), last)
    assert_eq(scan.workspace.live, live - 1)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
    )
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(scan.workspace.live, 0)
  }
}
