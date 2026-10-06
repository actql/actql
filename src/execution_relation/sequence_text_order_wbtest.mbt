///|
test "sequence identity sort yields inside a long equal Text prefix" {
  let mut prior_work : Int? = None
  for quantum in [1, 7] {
    let (_, execution, input) = bounded_sequence_fixture(text_keys=true)
    let state = bounded_sequence_match_state(execution)
    let mut completed : CompletedOutput? = None
    let mut comparisons = 0
    for _ in 0..<40000 {
      let before = state.control.remaining
      let sorting = state.phase is IdentitySort
      let result = advance_bounded_sequence_match(execution, quantum).unwrap()
      if sorting {
        assert_true(before - state.control.remaining <= quantum)
        comparisons += 1
      }
      match result {
        BoundedSequenceMatchContinue(..) => ()
        BoundedSequenceMatchComplete(output, ..) => {
          completed = Some(output)
          break
        }
        BoundedSequenceMatchFailed(_, ..) => fail("long sequence failed")
        BoundedSequenceMatchStopped(_, ..) => fail("long sequence stopped")
      }
    }
    assert_true(comparisons > 512)
    guard completed is Some(output) else {
      fail("long sequence did not finish")
    }
    assert_eq(completed_row_count(output), 3)
    let names = [
      "aux", "end_id", "end_time_ms", "key", "match_end_ms", "match_start_ms", "start_id",
      "start_time_ms",
    ]
    assert_eq(completed_column_count(output), names.length())
    for index in 0..<names.length() {
      assert_eq(completed_column_name(output, index), Some(names[index]))
    }
    for
      (row, end_id, end_time, key, start_id, start_time) in [
        (0, 2, 2, 1, 1, 1),
        (1, 3, 3, 1, 1, 1),
        (2, 4, 4, 2, 5, 3),
      ] {
      if key == 1 {
        assert_true(
          completed_cell(output, row, 0) is Some(Text(value)) &&
          value == String::make(256, 'q') + "😀",
        )
      } else {
        assert_true(completed_cell(output, row, 0) is Some(Null))
      }
      assert_true(
        completed_cell(output, row, 1) is Some(Text(id)) &&
        id == String::make(256, 'g') + end_id.to_string(),
      )
      assert_true(
        completed_cell(output, row, 2) is Some(Number(time)) &&
        time == end_time.to_double(),
      )
      assert_true(
        completed_cell(output, row, 3) is Some(Text(group)) &&
        group == String::make(256, 'p') + key.to_string(),
      )
      assert_true(
        completed_cell(output, row, 4) is Some(Number(time)) &&
        time == end_time.to_double(),
      )
      assert_true(
        completed_cell(output, row, 5) is Some(Number(time)) &&
        time == start_time.to_double(),
      )
      assert_true(
        completed_cell(output, row, 6) is Some(Text(id)) &&
        id == String::make(256, 'g') + start_id.to_string(),
      )
      assert_true(
        completed_cell(output, row, 7) is Some(Number(time)) &&
        time == start_time.to_double(),
      )
    }
    assert_true(completed_output_matches_inputs(output, [input]))
    let spent = 100000 - state.control.remaining
    if prior_work is Some(prior) {
      assert_eq(spent, prior)
    }
    prior_work = Some(spent)
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_bounded_sequence_scratch_reclaimed(execution)
  }
}

///|
test "sequence long output has an independently calculated workspace boundary" {
  // Five input names, two keys, five clocks, two pattern containers, ten
  // predicate cells and eight output names = 32 metadata slots. Five sorted
  // indices and three two-position matches add 14. The raw/checked output
  // row adds 9+8, and its stepped Text measure adds one: peak 64.
  for slots in [64, 63] {
    for quantum in [1, 7] {
      let (_, execution, input) = bounded_sequence_fixture(
        text_keys=true,
        max_entries=slots,
      )
      let mut terminal : BoundedSequenceMatchPoll? = None
      for _ in 0..<40000 {
        match advance_bounded_sequence_match(execution, quantum).unwrap() {
          BoundedSequenceMatchContinue(..) => ()
          value => {
            terminal = Some(value)
            break
          }
        }
      }
      if slots == 64 {
        assert_true(terminal is Some(BoundedSequenceMatchComplete(_, ..)))
        assert_eq(bounded_sequence_match_state(execution).workspace.peak, 64)
      } else {
        assert_true(
          terminal is Some(BoundedSequenceMatchFailed(Rows(RowLimit), ..)),
        )
        assert_true(bounded_sequence_match_state(execution).rows.val is None)
      }
      assert_true(cleanup_bounded_sequence_match(execution).unwrap())
      assert_bounded_sequence_scratch_reclaimed(execution)
      assert_true(producer_read_available(input))
    }
  }
}

///|
test "sequence keeps a long comparison and child sort until confirmed stop" {
  for target in 0..<4 {
    let (control, execution, input) = bounded_sequence_fixture(text_keys=true)
    let state = bounded_sequence_match_state(execution)
    let mut reached = false
    for _ in 0..<40000 {
      guard advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchContinue(..) else {
        fail("sequence terminated before its pending comparison")
      }
      let phase_matches = match target {
        0 => state.phase is IdentitySort
        1 => state.phase is CheckUnique
        2 => state.phase is OrderSort && state.compare_column == 1
        _ => state.phase is CompareGroupKey && state.compare_column == 1
      }
      if phase_matches &&
        state.comparison is Some(cursor) &&
        cursor.phase == 3 &&
        cursor.offset > 64 {
        reached = true
        break
      }
    }
    assert_true(reached)
    let held = state.workspace.live
    let remaining = state.control.remaining
    assert_true(@bounded.request_cancel(control))
    assert_true(state.comparison is Some(_))
    assert_eq(state.workspace.live, held)
    assert_true(
      advance_bounded_sequence_match(execution, 1).unwrap()
      is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
    )
    assert_true(state.comparison is Some(_))
    assert_eq(
      (state.workspace.live, state.control.remaining),
      (held, remaining),
    )
    assert_true(state.rows.val is None)
    assert_false(state.accepted.val)
    assert_true(producer_read_available(input))
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_false(cleanup_bounded_sequence_match(execution).unwrap())
    assert_true(state.comparison is None)
    assert_eq(state.compare_left, -1)
    assert_eq(state.control.remaining, remaining)
    assert_bounded_sequence_scratch_reclaimed(execution)
    assert_true(producer_read_available(input))
  }
}

///|
test "sequence comparison fixes byte work and pending cursor workspace" {
  // Isolate one production identity pair after normal column resolution.
  // Both 257-byte operands plus the complete-value transition require 515
  // control units. Existing five-row metadata needs 32 slots, then two
  // pending comparison handles. These are not whole-task work limits.
  for (work, slots, failure) in [(515, 34, 0), (514, 34, 1), (515, 33, 2)] {
    let (control, execution, input) = bounded_sequence_fixture(
      text_keys=true,
      max_entries=slots,
    )
    let state = bounded_sequence_match_state(execution)
    while state.identity_column == -1 {
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchContinue(..),
      )
    }
    state.control.remaining = work
    let mut result : Result[Int?, RowIssue] = Ok(None)
    for _ in 0..<2000 {
      result = bounded_sequence_compare_identity(state, 0, 1)
      if !(result is Ok(None)) {
        break
      }
    }
    match failure {
      0 => {
        assert_true(result is Ok(Some(value)) && value > 0)
        assert_eq(state.control.remaining, 0)
        assert_eq(state.workspace.peak, 34)
        assert_true(state.comparison is None)
        assert_eq(state.workspace.live, 32)
      }
      _ => assert_true(result is Err(RowLimit))
    }
    let remaining = state.control.remaining
    @bounded.request_cancel(control) |> ignore
    assert_true(
      advance_bounded_sequence_match(execution, 1).unwrap()
      is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
    )
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_eq(state.control.remaining, remaining)
    assert_bounded_sequence_scratch_reclaimed(execution)
    assert_true(producer_read_available(input))
  }
}
