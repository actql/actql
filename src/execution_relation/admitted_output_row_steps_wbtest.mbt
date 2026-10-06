///|
test "row output cursor preserves logical charges and commits under its existing owner" {
  let owner = capture_fixture()
  let limits : ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }
  let output = prepare_admitted_output(owner, Step(1), 2, limits).unwrap()
  for row in 0..<2 {
    let values = output_fixture_row(owner, row)
    let cursor = start_admitted_output_row(output, 4, column => {
      values.get(column).map(cell => cell.value)
    }).unwrap()
    let mut complete = false
    let mut polls = 0
    while !complete && polls < 13 {
      assert_true(finish_admitted_output(output) is Err(ClosedCapture))
      complete = advance_admitted_output_row(cursor).unwrap()
      polls += 1
    }
    assert_true(complete)
    assert_eq(polls, 13)
    assert_eq(cursor.workspace.peak, 3)
    assert_eq(cursor.workspace.live, 0)
    assert_true(cleanup_admitted_output_row(cursor))
    assert_false(cleanup_admitted_output_row(cursor))
    assert_eq(output.buffer.rows.length(), row + 1)
  }
  let rows = finish_admitted_output(output).unwrap()
  assert_eq(admitted_output_usage(rows), { nodes: 6, text_bytes: 10, work: 16, })
  assert_eq(admitted_output_row_count(rows), 2)
}

///|
test "completed row cleanup cannot unlock a subsequent provisional row" {
  let owner = capture_fixture()
  let output = prepare_admitted_output(owner, Step(1), 2, {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }).unwrap()
  let first_values = output_fixture_row(owner, 0)
  let first = start_admitted_output_row(output, 4, column => {
    first_values.get(column).map(value => value.value)
  }).unwrap()
  for _ in 0..<12 {
    assert_eq(advance_admitted_output_row(first), Ok(false))
  }
  assert_eq(advance_admitted_output_row(first), Ok(true))
  let next_values = output_fixture_row(owner, 1)
  let next = start_admitted_output_row(output, 4, column => {
    next_values.get(column).map(value => value.value)
  }).unwrap()
  assert_true(cleanup_admitted_output_row(first))
  assert_false(cleanup_admitted_output_row(first))
  assert_true(output.buffer.reading)
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  for _ in 0..<12 {
    assert_eq(advance_admitted_output_row(next), Ok(false))
  }
  assert_eq(advance_admitted_output_row(next), Ok(true))
  assert_true(cleanup_admitted_output_row(next))
  assert_eq(
    admitted_output_row_count(finish_admitted_output(output).unwrap()),
    2,
  )
}

///|
test "row output cursor retains failed custody until cleanup and rejects reentrancy" {
  let owner = capture_fixture()
  let values = output_fixture_row(owner, 0)
  let output = prepare_admitted_output(owner, Step(1), 2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 2,
    max_work: 1000,
  }).unwrap()
  append_admitted_output(output, values).unwrap()
  let rejected = Ref(false)
  let active = start_admitted_output_row(output, 4, column => {
    rejected.val = finish_admitted_output(output) is Err(ClosedCapture) &&
      append_admitted_output(output, values) is Err(ClosedCapture)
    if column == 1 {
      None
    } else {
      values.get(column).map(cell => cell.value)
    }
  }).unwrap()
  for _ in 0..<3 {
    assert_eq(advance_admitted_output_row(active), Ok(false))
  }
  assert_true(
    advance_admitted_output_row(active)
    is Err(OutputRowCapture(InvalidCheckedRow)),
  )
  assert_eq(output.buffer.rows.length(), 1)
  assert_true(rejected.val)
  assert_eq(active.workspace.live, 3)
  assert_true(active.read is Some(_))
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  assert_true(cleanup_admitted_output_row(active))
  assert_eq(active.workspace.live, 0)
  assert_true(active.read is None)
  assert_true(output.buffer.rows.is_empty())
  assert_false(cleanup_admitted_output_row(active))
}

///|
test "row output cursor distinguishes temporary workspace and logical one-short limits" {
  let owner = capture_fixture()
  let text = @admitted.text_value("x".repeat(128), 128).unwrap()
  let number = @admitted.number_value(1.0).unwrap()
  for workspace in [2, 3] {
    let output = prepare_admitted_output(owner, Step(1), 1, {
      max_nodes: 3,
      max_text_bytes: 130,
      max_depth: 2,
      max_work: 133,
    }).unwrap()
    if workspace == 2 {
      assert_true(
        start_admitted_output_row(output, workspace, column => {
          Some(if column == 0 { number } else { text })
        })
        is Err(OutputRowWorkspace),
      )
      assert_true(cancel_admitted_output(output))
    } else {
      let active = start_admitted_output_row(output, workspace, column => {
        Some(if column == 0 { number } else { text })
      }).unwrap()
      let mut failed = false
      for _ in 0..<20 {
        if !failed {
          match advance_admitted_output_row(active) {
            Err(OutputRowWorkspace) => failed = true
            Ok(false) => ()
            _ => fail("one-short measurement workspace must not commit")
          }
        }
      }
      assert_true(failed)
      assert_true(cleanup_admitted_output_row(active))
      assert_true(output.buffer.rows.is_empty())
    }
  }
  // One outer row and two cells: three nodes. Names n/s add two bytes to
  // the 128-byte Text, so logical work is 3 + 130, independently of polls.
  for
    limits in [
      { max_nodes: 3, max_text_bytes: 130, max_depth: 2, max_work: 133, },
      { max_nodes: 2, max_text_bytes: 130, max_depth: 2, max_work: 133, },
      { max_nodes: 3, max_text_bytes: 129, max_depth: 2, max_work: 133, },
      { max_nodes: 3, max_text_bytes: 130, max_depth: 2, max_work: 132, },
    ] {
    let exact = limits.max_nodes == 3 &&
      limits.max_text_bytes == 130 &&
      limits.max_work == 133
    let output = prepare_admitted_output(owner, Step(1), 1, limits).unwrap()
    let active = start_admitted_output_row(output, 4, column => {
      Some(if column == 0 { number } else { text })
    }).unwrap()
    let mut terminal = false
    let mut polls = 0
    while !terminal && polls < 20 {
      polls += 1
      match advance_admitted_output_row(active) {
        Ok(false) => ()
        Ok(true) => {
          assert_true(exact)
          assert_eq(polls, 17)
          assert_eq(active.workspace.peak, 4)
          let rows = finish_admitted_output(output).unwrap()
          assert_eq(admitted_output_row_count(rows), 1)
          assert_eq(admitted_output_usage(rows), {
            nodes: 3,
            text_bytes: 130,
            work: 133,
          })
          terminal = true
        }
        Err(OutputRowCapture(CaptureLimit)) => {
          assert_false(exact)
          assert_true(output.buffer.rows.is_empty())
          assert_true(finish_admitted_output(output) is Err(ClosedCapture))
          terminal = true
        }
        _ => fail("logical one-short must preserve the capture limit cause")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_admitted_output_row(active))
    assert_false(cleanup_admitted_output_row(active))
    assert_eq(active.workspace.live, 0)
  }
}

///|
test "row output cursor releases partial recheck and measurement exactly once" {
  let owner = capture_fixture()
  let text = @admitted.text_value("x".repeat(128), 128).unwrap()
  let number = @admitted.number_value(1.0).unwrap()
  // Poll six is between Text recheck chunks; poll fifteen is between logical
  // Text measurement chunks. Neither can expose the provisional row.
  for barrier in [6, 15] {
    let output = prepare_admitted_output(owner, Step(1), 1, {
      max_nodes: 3,
      max_text_bytes: 130,
      max_depth: 2,
      max_work: 133,
    }).unwrap()
    let active = start_admitted_output_row(output, 4, column => {
      Some(if column == 0 { number } else { text })
    }).unwrap()
    for _ in 0..<barrier {
      assert_eq(advance_admitted_output_row(active), Ok(false))
    }
    assert_true(output.buffer.rows.is_empty())
    assert_true(active.read is Some(_))
    assert_true(finish_admitted_output(output) is Err(ClosedCapture))
    assert_true(active.workspace.live > 0)
    assert_true(cleanup_admitted_output_row(active))
    assert_eq(active.workspace.live, 0)
    assert_true(active.read is None)
    assert_true(active.recheck is None)
    assert_true(active.charge is None)
    assert_false(cleanup_admitted_output_row(active))
    assert_eq(
      advance_admitted_output_row(active),
      Err(OutputRowCapture(ClosedCapture)),
    )
  }
}
