///|
fn sequence_position_fixture(
  overlap? : String = "disallow",
  contiguity? : String = "adjacent",
  positions? : Int = 16,
  max_work? : Int = 100000,
  max_entries? : Int = 10000,
) -> (@bounded.Control, BoundedSequenceMatchExecution, ProducerRead) raise {
  // One independent full-length match. All clocks are equal; explicit
  // identities determine their order. No result is taken from the evaluator.
  let rows = Array::makei(positions, index => {
    "{\"id\":" +
    (index + 1).to_string() +
    ",\"key\":1,\"clock\":1,\"value\":" +
    (if index == 0 { "1" } else { "2" }) +
    "}"
  }).join(",")
  let (control, result, input) = bounded_sequence_try_fixture(
    overlap~,
    contiguity~,
    extra_patterns=positions - 2,
    source_rows=Some("[" + rows + "]"),
    max_work~,
    max_entries~,
  )
  (control, result.unwrap(), input)
}

///|
fn sequence_position_scratch_entries(state : BoundedSequenceState) -> Int {
  let mut entries = state.copy_positions.length() +
    state.selected.length() +
    state.row_matches.length() +
    state.predicate_input.length() +
    state.input_names.length() +
    state.output_names.length() +
    state.key_columns.length() +
    state.identity_order.length() +
    state.ordered.length() +
    state.clocks.length() +
    state.output_row.length() +
    state.checked_row.length() +
    state.predicates.length() +
    state.partials.length() +
    state.matches.length()
  for cells in state.predicates {
    entries += cells.length()
  }
  for patterns in state.partials {
    entries += patterns.length()
    for partial in patterns {
      entries += partial.positions.length()
    }
  }
  for matched in state.matches {
    entries += matched.positions.length()
  }
  entries
}

///|
fn finish_sequence_position_cleanup(
  execution : BoundedSequenceMatchExecution,
) -> Int raise {
  let mut attempts = 0
  for _ in 0..<1000 {
    if !bounded_sequence_match_cleanup_pending(execution) {
      assert_bounded_sequence_scratch_reclaimed(execution)
      assert_eq(execution.state.copy_positions.length(), 0)
      assert_eq(execution.state.copy_reserved, 0)
      assert_true(execution.state.copy_source is None)
      assert_false(cleanup_bounded_sequence_match(execution).unwrap())
      return attempts
    }
    let before = sequence_position_scratch_entries(execution.state)
    cleanup_bounded_sequence_match(execution).unwrap() |> ignore
    let after = sequence_position_scratch_entries(execution.state)
    assert_true(after <= before)
    assert_true(before - after <= 64)
    attempts += 1
  }
  fail("sequence scratch cleanup did not finish")
}

///|
test "sequence match position copy yields before publishing a complete match" {
  let (control, execution, input) = sequence_position_fixture()
  let state = bounded_sequence_match_state(execution)
  let mut reached = false
  for _ in 0..<30000 {
    if state.phase is DisallowNext && state.pattern == 16 {
      reached = true
      break
    }
    assert_true(
      advance_bounded_sequence_match(execution, 1).unwrap()
      is BoundedSequenceMatchContinue(..),
    )
  }
  assert_true(reached)
  assert_eq(state.selected.length(), 16)
  assert_eq(state.matches.length(), 0)
  assert_true(
    advance_bounded_sequence_match(execution, 1).unwrap()
    is BoundedSequenceMatchContinue(..),
  )
  // The start transition cannot copy all sixteen positions in one resume.
  assert_eq(state.matches.length(), 0)
  assert_true(producer_read_available(input))
  assert_true(state.phase is CopyPositions)
  let remaining = state.control.remaining
  for index in 1..<=16 {
    assert_true(
      advance_bounded_sequence_match(execution, 1).unwrap()
      is BoundedSequenceMatchContinue(..),
    )
    assert_eq(state.copy_positions.length(), index)
    assert_eq(state.matches.length(), 0)
    assert_eq(state.control.remaining, remaining)
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_sequence_match(execution, 1).unwrap()
    is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
  )
  assert_eq(state.copy_positions.length(), 16)
  assert_true(state.rows.val is None)
  assert_true(state.workspace.live > 0)
  assert_true(finish_sequence_position_cleanup(execution) > 1)
  assert_true(producer_read_available(input))
}

///|
test "sequence positions preserve independent rows and logical work across quanta" {
  for overlap in ["allow", "disallow"] {
    for contiguity in ["adjacent", "subsequence"] {
      // Adjacent uses the wide copy counterexample. Subsequence uses four
      // positions: its combinatorial partial set is a separate finite demand,
      // not a reason to weaken the workspace limit for the wide fixture.
      let positions = if contiguity == "adjacent" { 16 } else { 4 }
      let remainder : Ref[Int?] = Ref(None)
      for quantum in [1, 7, 256] {
        let (_, execution, input) = sequence_position_fixture(
          overlap~,
          contiguity~,
          positions~,
        )
        let mut complete : CompletedOutput? = None
        let mut prior_work = 0L
        for _ in 0..<30000 {
          match advance_bounded_sequence_match(execution, quantum).unwrap() {
            BoundedSequenceMatchContinue(work~, ..) => {
              assert_true(work - prior_work <= quantum.to_int64())
              prior_work = work
            }
            BoundedSequenceMatchComplete(output, work~, ..) => {
              assert_true(work - prior_work <= quantum.to_int64())
              complete = Some(output)
              break
            }
            _ =>
              fail(
                "independent sequence did not complete: " +
                overlap +
                "/" +
                contiguity +
                "/" +
                quantum.to_string(),
              )
          }
        }
        let output = complete.unwrap()
        assert_eq(completed_row_count(output), 1)
        let fields = ["\"end_id\":2", "\"end_time_ms\":1"]
        // Explicit UTF-16 field order, not the implementation's comparator.
        for index in [0, 10, 11, 12, 13, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
          if index >= positions - 2 {
            continue
          }
          fields.push(
            "\"extra_" + index.to_string() + "_id\":" + (index + 3).to_string(),
          )
          fields.push("\"extra_" + index.to_string() + "_time_ms\":1")
        }
        fields.push("\"key\":1")
        fields.push("\"match_end_ms\":1")
        fields.push("\"match_start_ms\":1")
        fields.push("\"start_id\":1")
        fields.push("\"start_time_ms\":1")
        assert_eq(
          completed_output_row_wire(output, 0, 10000, 1000, 20).unwrap(),
          "{" + fields.join(",") + "}",
        )
        match remainder.val {
          None => remainder.val = Some(execution.state.control.remaining)
          Some(value) => assert_eq(execution.state.control.remaining, value)
        }
        assert_true(finish_sequence_position_cleanup(execution) > 0)
        assert_true(completed_output_available(output))
        assert_eq(
          completed_output_row_wire(output, 0, 10000, 1000, 20).unwrap(),
          "{" + fields.join(",") + "}",
        )
        assert_true(producer_read_available(input))
      }
    }
  }
}

///|
test "sequence position reserve rejects one short before copying" {
  // At the disallow match boundary: four input names, one key, sixteen clocks,
  // sixteen predicate containers, 256 predicate cells, 35 output names,
  // sixteen ordering indices and sixteen selected positions. The independent
  // destination adds sixteen positions and one match record: 360 + 17 = 377.
  let live = 4 + 1 + 16 + 16 + 16 * 16 + 35 + 16 + 16
  for (limit, succeeds) in [(live + 17, true), (live + 16, false)] {
    let (control, execution, input) = sequence_position_fixture(
      max_entries=limit,
    )
    let state = execution.state
    let mut reached = false
    for _ in 0..<30000 {
      if state.phase is DisallowNext && state.pattern == 16 {
        reached = true
        break
      }
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchContinue(..),
      )
    }
    assert_true(reached)
    assert_eq(state.workspace.live, live)
    let result = advance_bounded_sequence_match(execution, 1).unwrap()
    assert_eq(state.copy_positions.length(), 0)
    assert_eq(state.matches.length(), 0)
    if succeeds {
      assert_true(result is BoundedSequenceMatchContinue(..))
      assert_eq(state.copy_reserved, 17)
      assert_eq(state.workspace.live, live + 17)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
      )
    } else {
      assert_true(result is BoundedSequenceMatchFailed(Rows(RowLimit), ..))
      assert_eq(state.copy_reserved, 0)
      assert_eq(state.workspace.live, live)
    }
    finish_sequence_position_cleanup(execution) |> ignore
    assert_true(producer_read_available(input))
  }
}

///|
test "sequence wide subsequence retains its finite partial capacity refusal" {
  // A start followed by fifteen matching events creates every increasing
  // subset as a partial. Even the 6435 eight-position subsets alone require
  // 51480 position slots, independently exceeding this 10000-slot fixture.
  let (_, execution, input) = sequence_position_fixture(
    overlap="allow",
    contiguity="subsequence",
    max_entries=10000,
  )
  assert_true(
    finish_bounded_sequence(execution)
    is BoundedSequenceMatchFailed(Rows(RowLimit), ..),
  )
  assert_true(execution.state.rows.val is None)
  assert_false(execution.state.accepted.val)
  finish_sequence_position_cleanup(execution) |> ignore
  assert_true(producer_read_available(input))
}

///|
test "sequence cancels position copying and collection release without losing custody" {
  for boundary in [0, 1, 2, 3, 4, 5] {
    let (control, execution, input) = sequence_position_fixture(
      overlap=if boundary < 2 || boundary == 3 { "allow" } else { "disallow" },
    )
    let state = execution.state
    let mut reached = false
    for _ in 0..<30000 {
      let at_boundary = match boundary {
        0 =>
          state.phase is CopyPositions &&
          state.copy_kind is ExtendPartial &&
          state.copy_positions.length() == 8
        1 =>
          state.phase is CopyPositions &&
          state.copy_kind is MatchAllow &&
          state.copy_positions.length() == 8
        2 => state.phase is ReleaseSelected && state.selected.length() == 8
        3 => state.phase is ReleaseGroup
        4 =>
          state.phase is ReleaseMatches &&
          state.matches[0].positions.length() == 8
        _ =>
          state.phase is ReleasePredicateInput &&
          state.predicate_input.length() == 2
      }
      if at_boundary {
        reached = true
        break
      }
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchContinue(..),
      )
    }
    assert_true(reached)
    let held = state.workspace.live
    assert_true(@bounded.request_cancel(control))
    assert_eq(state.workspace.live, held)
    assert_true(producer_read_available(input))
    assert_true(
      advance_bounded_sequence_match(execution, 1).unwrap()
      is BoundedSequenceMatchStopped(@bounded.Cancelled, ..),
    )
    assert_eq(state.workspace.live, held)
    assert_true(state.rows.val is None)
    assert_false(state.accepted.val)
    // The 256-cell matrix alone requires more than one 64-entry cleanup.
    assert_false(cleanup_bounded_sequence_match(execution).unwrap())
    assert_true(bounded_sequence_match_cleanup_pending(execution))
    assert_true(state.workspace.live > 0)
    let remaining = state.control.remaining
    assert_true(finish_sequence_position_cleanup(execution) > 0)
    assert_eq(state.control.remaining, remaining)
    assert_true(producer_read_available(input))
  }
}
