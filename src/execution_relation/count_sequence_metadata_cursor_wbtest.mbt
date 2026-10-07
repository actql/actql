///|
test "count metadata resumes long Unicode names without changing groups" {
  let key = "id" + "x".repeat(128) + "😀é"
  let count_label = "n" + "y".repeat(128) + "😀é"
  let logical_remaining : Ref[Int?] = Ref(None)
  for quantum in [1, 7, 256] {
    let (_, execution, source) = bounded_global_count_fixture(
      "[{\"id\":1},{\"id\":null},{\"id\":1}]",
      keyed=true,
      input_name=key,
      count_name=count_label,
      max_work=10000,
    )
    let state = execution.state
    let mut result = None
    for _ in 0..<20000 {
      let remaining = state.control.remaining
      match advance_bounded_global_count(execution, quantum).unwrap() {
        BoundedGlobalCountContinue(..) => ()
        BoundedGlobalCountComplete(output, ..) => {
          result = Some(output)
          break
        }
        _ => fail("long-name COUNT did not complete")
      }
      if state.phase is ResolveInput ||
        state.phase is ResolveKeys ||
        state.phase is ResolveAggregates ||
        state.phase is ResolveOutput {
        assert_true(remaining - state.control.remaining <= 4 * quantum)
      }
    }
    let output = result.unwrap()
    match logical_remaining.val {
      None => logical_remaining.val = Some(state.control.remaining)
      Some(remaining) => assert_eq(state.control.remaining, remaining)
    }
    assert_eq(completed_row_count(output), 2)
    for
      (row, expected) in [
        (0, "{\"" + key + "\":null,\"" + count_label + "\":1,\"present\":0}"),
        (1, "{\"" + key + "\":1,\"" + count_label + "\":2,\"present\":2}"),
      ] {
      assert_eq(
        completed_output_row_wire(output, row, 10000, 1000, 20).unwrap(),
        expected,
      )
    }
    assert_true(cleanup_bounded_global_count(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
}

///|
test "count long name value budgets retain exact one short and atomic charging" {
  let key = "id" + "x".repeat(128) + "😀é"
  // UTF-8 input spelling: id=2, ASCII run=128, emoji=4, accent=2.
  // One output row adds n=1 and present=7 to the 136-byte input name.
  let input_required = 2 + 128 + 4 + 2
  let output_required = input_required + 1 + 7
  for
    (input_bytes, output_bytes, success, input_failure) in [
      (input_required, output_required, true, false),
      (input_required - 1, output_required, false, true),
      (input_required, output_required - 1, false, false),
    ] {
    let input_values = {
      ..run_limits().input_values,
      max_text_bytes: input_bytes,
    }
    let output_values = {
      ..run_limits().output_values,
      max_text_bytes: output_bytes,
    }
    let (_, execution, source) = bounded_global_count_fixture(
      "[{\"id\":1}]",
      keyed=true,
      input_name=key,
      max_work=10000,
      input_values~,
      output_values~,
    )
    let state = execution.state
    let mut finished = false
    let mut failed = false
    for _ in 0..<10000 {
      // Name bytes are committed as one value-budget charge only after the
      // cursor is complete, while scalar scanning remains cancellable.
      if state.phase is ChargeInput &&
        state.name_charge is Some(cursor) &&
        cursor.offset == 64 {
        assert_eq(state.input_values.text, 0)
      }
      match advance_bounded_global_count(execution, 1).unwrap() {
        BoundedGlobalCountContinue(..) => ()
        BoundedGlobalCountComplete(output, ..) => {
          assert_eq(completed_row_count(output), 1)
          assert_eq(state.input_values.text, input_required)
          finished = true
          break
        }
        BoundedGlobalCountFailed(InputLimit, ..) if input_failure => {
          failed = true
          break
        }
        BoundedGlobalCountFailed(Capture(CaptureLimit), ..) if !input_failure => {
          failed = true
          break
        }
        BoundedGlobalCountFailed(Rows(_), ..) =>
          fail("unexpected COUNT row failure instead of the value-name limit")
        BoundedGlobalCountFailed(Capture(_), ..) =>
          fail(
            "unexpected COUNT capture failure instead of the value-name limit",
          )
        BoundedGlobalCountFailed(Completion(_), ..) =>
          fail(
            "unexpected COUNT completion failure instead of the value-name limit",
          )
        BoundedGlobalCountFailed(InputLimit, ..) =>
          fail(
            "COUNT input limit at " +
            input_bytes.to_string() +
            "/" +
            output_bytes.to_string(),
          )
        _ => fail("incorrect COUNT value-name limit cause")
      }
    }
    assert_eq((finished, failed), (success, !success))
    if !success {
      assert_true(state.rows.val is None)
      assert_false(state.accepted.val)
    }
    assert_true(cleanup_bounded_global_count(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
}

///|
test "count metadata preserves independent exact and one short work" {
  // id bytes occur in input, key, source and output. n and present occur
  // twice; four entry charges are independent of lookup candidate count.
  for key in ["id", "id" + "x".repeat(128) + "😀é"] {
    let bytes = if key == "id" { 2 } else { 2 + 128 + 4 + 2 }
    let required = 4 * bytes + 20
    for (budget, success) in [(required, true), (required - 1, false)] {
      let (control, execution, source) = bounded_global_count_fixture(
        "[]",
        keyed=true,
        input_name=key,
        max_work=budget,
      )
      let state = execution.state
      let mut resolved = false
      let mut failed = false
      for _ in 0..<10000 {
        match advance_bounded_global_count(execution, 1).unwrap() {
          BoundedGlobalCountContinue(..) => ()
          BoundedGlobalCountFailed(Rows(RowLimit), ..) => {
            failed = true
            break
          }
          _ => fail("unexpected COUNT metadata terminal")
        }
        if state.phase is ResolveOutput && state.field == 3 {
          resolved = true
          break
        }
      }
      assert_eq((resolved, failed), (success, !success))
      if success {
        assert_eq(state.control.remaining, 0)
        assert_true(@bounded.request_cancel(control))
        assert_true(
          advance_bounded_global_count(execution, 1).unwrap()
          is BoundedGlobalCountStopped(_, ..),
        )
      }
      assert_true(state.rows.val is None)
      assert_true(cleanup_bounded_global_count(execution).unwrap())
      assert_false(cleanup_bounded_global_count(execution).unwrap())
      assert_eq(state.workspace.live, 0)
      assert_true(completed_output_available(source))
    }
  }
}

///|
test "count and sequence metadata reserve exact and one short workspace" {
  for (limit, success) in [(12, true), (11, false)] {
    let (control, execution, source) = bounded_global_count_fixture(
      "[]",
      keyed=true,
      input_name="id" + "x".repeat(128),
      max_work=10000,
      max_entries=limit,
    )
    let state = execution.state
    let mut resolved = false
    let mut failed = false
    for _ in 0..<10000 {
      match advance_bounded_global_count(execution, 1).unwrap() {
        BoundedGlobalCountContinue(..) => ()
        BoundedGlobalCountFailed(Rows(RowLimit), ..) => {
          failed = true
          break
        }
        _ => fail("unexpected COUNT workspace terminal")
      }
      if state.phase is ResolveOutput && state.field == 3 {
        resolved = true
        break
      }
    }
    // Input ordinals/names=2, key=1, aggregates=6, output columns=3.
    // Cursor ownership overlaps the still-unfilled metadata slot, not an
    // extra full-array copy. These independently sum to twelve slots.
    assert_eq((resolved, failed), (success, !success))
    if success {
      assert_eq(state.workspace.peak, 12)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        advance_bounded_global_count(execution, 1).unwrap()
        is BoundedGlobalCountStopped(_, ..),
      )
    }
    assert_true(cleanup_bounded_global_count(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
  for (limit, success) in [(15, true), (14, false)] {
    let (control, result, input) = bounded_sequence_try_fixture(
      empty=true,
      key_name=Some("key" + "x".repeat(128)),
      max_entries=limit,
    )
    let execution = result.unwrap()
    let state = bounded_sequence_match_state(execution)
    let mut resolved = false
    let mut failed = false
    for _ in 0..<10000 {
      match advance_bounded_sequence_match(execution, 1).unwrap() {
        BoundedSequenceMatchContinue(..) => ()
        BoundedSequenceMatchFailed(Rows(RowLimit), ..) => {
          failed = true
          break
        }
        _ => fail("unexpected Sequence workspace terminal")
      }
      if state.resolve_field == 3 {
        resolved = true
        break
      }
    }
    // Empty input: 4 input names + key + 2 pattern arrays + 7 output names
    // reserve fourteen slots; the pending schema lookup needs one more.
    assert_eq((resolved, failed), (success, !success))
    if success {
      assert_eq(state.workspace.peak, 15)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchStopped(_, ..),
      )
    }
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_bounded_sequence_scratch_reclaimed(execution)
    assert_true(producer_read_available(input))
  }
}

///|
test "count cancellation retains inputs within every name processing phase" {
  for boundary in [0, 1, 2, 3, 4, 5] {
    let (control, execution, source) = bounded_global_count_fixture(
      "[{\"id\":1}]",
      keyed=true,
      input_name="id" + "x".repeat(128) + "😀é",
      count_name="n" + "y".repeat(128),
      max_work=10000,
    )
    let state = execution.state
    let mut reached = false
    for _ in 0..<20000 {
      assert_true(
        advance_bounded_global_count(execution, 1).unwrap()
        is BoundedGlobalCountContinue(..),
      )
      reached = if boundary == 1 {
        state.metadata_lookup is Some(cursor) && cursor.offset == 64
      } else {
        state.name_charge is Some(cursor) &&
        cursor.offset == 64 &&
        (if boundary == 0 {
          state.phase is ResolveInput
        } else if boundary == 2 {
          state.phase is ResolveAggregates
        } else if boundary == 3 {
          state.phase is ResolveOutput
        } else if boundary == 4 {
          state.phase is ChargeInput
        } else {
          state.phase is BuildOutput
        })
      }
      if reached {
        break
      }
    }
    assert_true(reached)
    let live = state.workspace.live
    let remaining = state.control.remaining
    assert_true(@bounded.request_cancel(control))
    assert_eq(state.workspace.live, live)
    assert_true(
      advance_bounded_global_count(execution, 1).unwrap()
      is BoundedGlobalCountStopped(_, ..),
    )
    assert_eq(
      (state.workspace.live, state.control.remaining),
      (live, remaining),
    )
    assert_false(state.accepted.val)
    assert_true(state.rows.val is None)
    assert_true(cleanup_bounded_global_count(execution).unwrap())
    assert_false(cleanup_bounded_global_count(execution).unwrap())
    assert_eq(state.workspace.live, 0)
    assert_true(state.metadata_lookup is None && state.name_charge is None)
    assert_true(completed_output_available(source))
  }
}

///|
test "sequence metadata resumes long Unicode keys snapshots and pattern roles" {
  let key = "key" + "x".repeat(128) + "😀é"
  let label = "start" + "y".repeat(128) + "😀é"
  let logical_remaining : Ref[Int?] = Ref(None)
  for quantum in [1, 7, 256] {
    let (_, result, input) = bounded_sequence_try_fixture(
      key_name=Some(key),
      start_name=label,
    )
    let execution = result.unwrap()
    let state = bounded_sequence_match_state(execution)
    let mut complete = None
    for _ in 0..<30000 {
      let before = state.control.remaining
      match advance_bounded_sequence_match(execution, quantum).unwrap() {
        BoundedSequenceMatchContinue(..) => ()
        BoundedSequenceMatchComplete(output, ..) => {
          complete = Some(output)
          break
        }
        _ => fail("long-name sequence did not complete")
      }
      if state.phase is ResolveColumns || state.phase is BuildPredicateInput {
        assert_true(before - state.control.remaining <= 4 * quantum)
      }
    }
    let output = complete.unwrap()
    match logical_remaining.val {
      None => logical_remaining.val = Some(state.control.remaining)
      Some(remaining) => assert_eq(state.control.remaining, remaining)
    }
    assert_eq(completed_row_count(output), 3)
    // Hand-authored matches are (1,2), (1,3), and (5,4).
    for
      (row, end_id, end_time, group, start_id, start_time) in [
        (0, 2, 2, 1, 1, 1),
        (1, 3, 3, 1, 1, 1),
        (2, 4, 4, 2, 5, 3),
      ] {
      let expected = "{\"end_id\":" +
        end_id.to_string() +
        ",\"end_time_ms\":" +
        end_time.to_string() +
        ",\"" +
        key +
        "\":" +
        group.to_string() +
        ",\"match_end_ms\":" +
        end_time.to_string() +
        ",\"match_start_ms\":" +
        start_time.to_string() +
        ",\"" +
        label +
        "_id\":" +
        start_id.to_string() +
        ",\"" +
        label +
        "_time_ms\":" +
        start_time.to_string() +
        "}"
      assert_eq(
        completed_output_row_wire(output, row, 10000, 1000, 20).unwrap(),
        expected,
      )
    }
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_bounded_sequence_scratch_reclaimed(execution)
    assert_true(producer_read_available(input))
  }
}

///|
test "sequence metadata preserves long name exact and one short work" {
  // key lookup visits clock,id,key: 3 entries + 4 key spellings + 7
  // candidate bytes. id costs 13; clock costs 11. Key has 137 UTF-8 bytes.
  let required = 3 + 4 * (3 + 128 + 4 + 2) + 7 + 13 + 11
  for (limit, success) in [(required, true), (required - 1, false)] {
    let (control, result, input) = bounded_sequence_try_fixture(
      empty=true,
      key_name=Some("key" + "x".repeat(128) + "😀é"),
      max_work=limit,
    )
    let execution = result.unwrap()
    let state = bounded_sequence_match_state(execution)
    let mut resolved = false
    let mut failed = false
    for _ in 0..<10000 {
      match advance_bounded_sequence_match(execution, 1).unwrap() {
        BoundedSequenceMatchContinue(..) => ()
        BoundedSequenceMatchFailed(Rows(RowLimit), ..) => {
          failed = true
          break
        }
        _ => fail("unexpected Sequence metadata terminal")
      }
      if state.resolve_field == 3 {
        resolved = true
        break
      }
    }
    assert_eq((resolved, failed), (success, !success))
    if success {
      assert_eq(state.control.remaining, 0)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchStopped(_, ..),
      )
    }
    assert_true(state.rows.val is None)
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_bounded_sequence_scratch_reclaimed(execution)
    assert_true(producer_read_available(input))
  }
}

///|
test "sequence cancellation retains snapshots at lookup predicate and output boundaries" {
  for boundary in [0, 1, 2, 3] {
    let (control, result, input) = bounded_sequence_try_fixture(
      key_name=Some("key" + "x".repeat(128) + "😀é"),
      start_name="start" + "y".repeat(128) + "😀é",
    )
    let execution = result.unwrap()
    let state = bounded_sequence_match_state(execution)
    let mut reached = false
    for _ in 0..<30000 {
      assert_true(
        advance_bounded_sequence_match(execution, 1).unwrap()
        is BoundedSequenceMatchContinue(..),
      )
      reached = if boundary == 0 {
        state.metadata_lookup is Some(cursor) &&
        cursor.phase == 3 &&
        cursor.lookup.offset == 64
      } else if boundary == 1 {
        state.phase is BuildPredicateInput &&
        state.name_charge is Some(cursor) &&
        cursor.offset == 64
      } else if boundary == 2 {
        state.phase is ResolveOutputPattern &&
        state.output_label_charge.offset == 64
      } else {
        state.phase is ResolveOutputPattern && state.output_name_offset == 64
      }
      if reached {
        break
      }
    }
    assert_true(reached)
    let live = state.workspace.live
    let remaining = state.control.remaining
    assert_true(@bounded.request_cancel(control))
    assert_eq(state.workspace.live, live)
    assert_true(
      advance_bounded_sequence_match(execution, 1).unwrap()
      is BoundedSequenceMatchStopped(_, ..),
    )
    assert_eq(
      (state.workspace.live, state.control.remaining),
      (live, remaining),
    )
    assert_false(state.accepted.val)
    assert_true(state.rows.val is None)
    assert_true(cleanup_bounded_sequence_match(execution).unwrap())
    assert_false(cleanup_bounded_sequence_match(execution).unwrap())
    assert_bounded_sequence_scratch_reclaimed(execution)
    assert_true(producer_read_available(input))
  }
}
