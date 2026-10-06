///|
test "string aggregation yields while sizing a long contributor" {
  let control = { remaining: 256, max_frames: 0, }
  let state = start_aggregate_string(
    [Text("x".repeat(256))],
    "",
    256L,
    control,
    row_workspace(300),
  ).unwrap()
  for _ in 0..<4 {
    assert_true(advance_aggregate_string(state).unwrap() is None)
    assert_eq(state.total, 0L)
    assert_eq(control.remaining, 256)
  }
}

///|
test "string aggregation has independent UTF8 work capacity and buffer limits" {
  let first = "x".repeat(63) + "😀" + "e\u{0301}\r\n"
  let delimiter = "d".repeat(65) + "\r\n"
  let values = [Text(first), Text("end")]
  // Bytes 72+67+3=142; units 69+67+3=139; state/builder two handles.
  for quantum in [1, 7, 256] {
    for
      (work, maximum, slots, success) in [
        (142, 142L, 141, true),
        (141, 142L, 141, false),
        (142, 141L, 141, false),
        (142, 142L, 140, false),
      ] {
      let control = { remaining: work, max_frames: 0, }
      let workspace = row_workspace(slots)
      let state = start_aggregate_string(
        values, delimiter, maximum, control, workspace,
      ).unwrap()
      let mut result : Result[Value?, RowIssue] = Ok(None)
      for _ in 0..<1000 {
        for _ in 0..<quantum {
          if result is Ok(None) {
            let before = control.remaining
            result = advance_aggregate_string(state)
            assert_true(before - control.remaining <= 1)
          }
        }
      }
      if success {
        assert_true(
          result is Ok(Some(Text(actual))) &&
          actual == first + delimiter + "end",
        )
        assert_eq(
          (control.remaining, workspace.peak, workspace.live),
          (0, 141, 139),
        )
        close_aggregate_string(state)
        assert_eq(workspace.live, 139)
        release_slots(workspace, 139)
      } else {
        assert_true(result is Err(RowLimit))
        // The one-short byte ceiling fails before charging the second item;
        // work/workspace failures occur after their independently fixed charge.
        assert_eq(control.remaining, if maximum == 141L { 70 } else { 0 })
        assert_eq(state.total, if maximum == 141L { 72L } else { 142L })
        assert_eq(workspace.live, 0)
        assert_true(state.builder is None)
      }
      assert_eq(workspace.live, 0)
    }
  }
}

///|
test "string aggregation cancellation closes delimiter item charge and building phases" {
  let text = "x".repeat(256)
  let delimiter = "d".repeat(256)
  for target in [0, 2, 3, 5] {
    let values = [Text(text), Text("end")]
    let workspace = row_workspace(600)
    let control = { remaining: 1000, max_frames: 0, }
    let state = start_aggregate_string(
      values, delimiter, 515L, control, workspace,
    ).unwrap()
    let mut inside = false
    for _ in 0..<2000 {
      if !inside {
        assert_true(advance_aggregate_string(state).unwrap() is None)
        inside = state.phase == target &&
          (if target == 3 {
            state.pending == 128L
          } else if target == 5 {
            state.emitted == 64
          } else {
            state.offset == 64
          })
      }
    }
    assert_true(inside)
    let remaining = control.remaining
    close_aggregate_string(state)
    close_aggregate_string(state)
    assert_eq((control.remaining, workspace.live), (remaining, 0))
    assert_true(state.builder is None)
    assert_true(values[0] is Text(actual) && actual == text)
    assert_true(advance_aggregate_string(state) is Err(InvalidRows))
  }
}

///|
test "string aggregation preserves undemanded delimiters empty text and malformed refusal" {
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  for
    (values, maximum, expected, work) in [
      ([], -1L, "", 0),
      ([Text("")], 0L, "", 0),
      ([Text("x")], 1L, "x", 1),
    ] {
    let workspace = row_workspace(3)
    let control = { remaining: work, max_frames: 0, }
    let state = start_aggregate_string(
      values, malformed, maximum, control, workspace,
    ).unwrap()
    let mut result : Result[Value?, RowIssue] = Ok(None)
    for _ in 0..<30 {
      if result is Ok(None) {
        result = advance_aggregate_string(state)
      }
    }
    assert_true(result is Ok(Some(Text(actual))) && actual == expected)
    assert_eq(control.remaining, 0)
    release_slots(workspace, workspace.live)
  }
  for
    (values, delimiter) in [
      ([Text("a"), Text("b")], malformed),
      ([Text(malformed)], ""),
    ] {
    let workspace = row_workspace(10)
    let control = { remaining: 100, max_frames: 0, }
    let state = start_aggregate_string(
      values, delimiter, 100L, control, workspace,
    ).unwrap()
    let mut result : Result[Value?, RowIssue] = Ok(None)
    for _ in 0..<20 {
      if result is Ok(None) {
        result = advance_aggregate_string(state)
      }
    }
    assert_true(result is Err(RowLimit))
    assert_eq(workspace.live, 0)
  }
  assert_true(
    start_aggregate_string(
      [Text("x")],
      "",
      1L,
      { remaining: 1, max_frames: 0, },
      row_workspace(1),
    )
    is Err(RowLimit),
  )
}
