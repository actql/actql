///|
test "join metadata yields within long Unicode source and output names" {
  for quantum in [1, 7, 256] {
    let (_, execution, reads) = bounded_join_fixture(
      key_name="x".repeat(128) + "😀é",
      right_name="y".repeat(256),
    )
    let mut output = None
    for _ in 0..<10000 {
      let before = execution.state.control.remaining
      let poll = advance_bounded_join(execution, quantum).unwrap()
      // Every metadata fragment consumes at most one scalar (four bytes).
      // Input and output phases have their own existing accounting tests.
      if execution.state.phase is ResolveKeySource ||
        execution.state.phase is ResolveSource ||
        execution.state.phase is ChargeOutputName {
        assert_true(before - execution.state.control.remaining <= 4 * quantum)
      }
      match poll {
        BoundedJoinContinue(..) => ()
        BoundedJoinComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("long-name Join failed")
      }
    }
    let value = output.unwrap()
    assert_eq(completed_row_count(value), 1)
    assert_true(
      join_numeric_rows_equal(
        [
          [
            completed_cell(value, 0, 0).unwrap(),
            completed_cell(value, 0, 1).unwrap(),
            completed_cell(value, 0, 2).unwrap(),
          ],
        ],
        [[Number(1), Number(10), Number(20)]],
      ),
    )
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(reads.all(producer_read_available))
  }
}

///|
test "join metadata preserves literal exact and one short preparation work" {
  for (limit, success) in [(23, true), (22, false)] {
    let (control, execution, reads) = bounded_join_fixture()
    let state = execution.state
    for _ in 0..<1000 {
      if state.phase is ResolveKey {
        break
      }
      assert_true(
        advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
      )
    }
    assert_true(state.phase is ResolveKey)
    // id,v schema: two id key lookups = 6, k/l/r output names = 6,
    // projected id = 3 and projected v twice = 4 + 4, totaling 23.
    state.control.remaining = limit
    let mut finished = false
    let mut failed = false
    for _ in 0..<1000 {
      match advance_bounded_join(execution, 1).unwrap() {
        BoundedJoinContinue(..) => ()
        BoundedJoinFailed(Rows(RowLimit), ..) => {
          failed = true
          break
        }
        _ => fail("unexpected Join metadata terminal")
      }
      if state.phase is ResolveField && state.field == 3 {
        finished = true
        break
      }
    }
    assert_eq((finished, failed), (success, !success))
    if success {
      assert_eq(state.control.remaining, 0)
      assert_eq(state.pairs.keys, [(0, 0)])
      assert_eq(state.columns, [(true, 0), (true, 1), (false, 1)])
      assert_eq(state.names, ["k", "l", "r"])
      assert_true(@bounded.request_cancel(control))
      assert_true(
        advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
      )
    }
    assert_true(state.rows.val is None)
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_false(cleanup_bounded_join(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(reads.all(producer_read_available))
  }
}

///|
test "join cancellation retains borrowed inputs at each metadata cursor boundary" {
  for boundary in [0, 1, 2, 3] {
    let (control, execution, reads) = bounded_join_fixture(
      key_name="x".repeat(128) + "😀é",
      right_name="y".repeat(256),
    )
    let state = execution.state
    let mut reached = false
    for _ in 0..<10000 {
      assert_true(
        advance_bounded_join(execution, 1).unwrap() is BoundedJoinContinue(..),
      )
      reached = if boundary == 3 {
        state.name_charge is Some(cursor) && cursor.offset == 128
      } else {
        match state.metadata_lookup {
          Some(cursor) =>
            if boundary == 0 {
              cursor.phase == 0
            } else if boundary == 1 {
              cursor.phase == 1 && cursor.offset == 64
            } else {
              cursor.phase == 3 && cursor.lookup.offset == 64
            }
          None => false
        }
      }
      if reached {
        break
      }
    }
    assert_true(reached)
    let live = state.workspace.live
    let remaining = state.control.remaining
    assert_true(live > 0)
    assert_true(@bounded.request_cancel(control))
    assert_true(reads.all(producer_read_available))
    assert_eq(state.workspace.live, live)
    assert_true(
      advance_bounded_join(execution, 1).unwrap() is BoundedJoinStopped(_, ..),
    )
    assert_eq(
      (state.control.remaining, state.workspace.live),
      (remaining, live),
    )
    assert_true(state.rows.val is None)
    assert_false(state.accepted.val)
    assert_true(cleanup_bounded_join(execution).unwrap())
    assert_false(cleanup_bounded_join(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(state.metadata_lookup is None && state.name_charge is None)
    assert_true(reads.all(producer_read_available))
  }
}
