///|
test "charged schema lookup preserves independent UTF8 work and workspace limits" {
  let name = "x".repeat(128) + "😀é"
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Qualified(@schema.Left, name), contract),
      (@schema.Qualified(@schema.Right, name), contract),
    ],
    max_fields=2,
    max_name_bytes=1000,
  ).unwrap()
  // Target bytes: 6 + 128 + 4 + 2 = 140, charged for two candidates.
  // Nest also charges candidate bytes: 139 + 140. No product measurement.
  for (candidate, exact) in [(false, 282), (true, 561)] {
    for (limit, success) in [(exact, true), (exact - 1, false)] {
      for quantum in [1, 7, 256] {
        let workspace = row_workspace(1)
        let control : ControlBudget = { remaining: limit, max_frames: 10, }
        let cursor = start_charged_row_metadata_lookup(
          schema,
          @schema.Qualified(@schema.Right, name),
          workspace,
          candidate,
        ).unwrap()
        let mut terminal : Result[Int, RowIssue]? = None
        for _ in 0..<1200 {
          for _ in 0..<quantum {
            if terminal is None {
              let before = control.remaining
              match advance_charged_row_metadata_lookup(cursor, control) {
                Ok(None) => ()
                Ok(Some(column)) => terminal = Some(Ok(column))
                Err(issue) => terminal = Some(Err(issue))
              }
              assert_true(before - control.remaining <= 4)
            }
          }
          if terminal is Some(_) {
            break
          }
        }
        if success {
          assert_true(terminal is Some(Ok(1)))
          assert_eq(control.remaining, 0)
        } else {
          assert_true(terminal is Some(Err(RowLimit)))
        }
        close_row_metadata_lookup(cursor.lookup)
        close_row_metadata_lookup(cursor.lookup)
        assert_eq((workspace.peak, workspace.live), (1, 0))
      }
    }
    assert_true(
      start_charged_row_metadata_lookup(
        schema,
        @schema.Qualified(@schema.Right, name),
        row_workspace(0),
        candidate,
      )
      is None,
    )
  }
}

///|
test "temporal metadata starts uncharged and preserves literal preparation boundaries" {
  for quantum in [1, 7, 256] {
    for (work, success) in [(118, true), (117, false)] {
      let (_, active, inputs) = bounded_interval_fixture()
      assert_eq(active.state.control.remaining, 100000)
      assert_true(
        active.state.keys.is_empty() && active.state.columns.is_empty(),
      )
      while !(active.state.phase is ResolveMetadata) {
        assert_true(
          advance_bounded_interval_join(active, 1).unwrap()
          is BoundedIntervalJoinContinue(..),
        )
      }
      // Sorted end,key,start,time,value: keys 16, clocks 20+18+4,
      // output sources 30+30. The cursor does not change that 118-unit sum.
      active.state.control.remaining = work
      let mut finished = false
      let mut failed = false
      for _ in 0..<1000 {
        match advance_bounded_interval_join(active, 1).unwrap() {
          BoundedIntervalJoinContinue(..) => ()
          BoundedIntervalJoinFailed(InvalidExecution, ..) => {
            failed = true
            break
          }
          _ => fail("unexpected interval preparation terminal")
        }
        if active.state.phase is ReadLeftClocks {
          finished = true
          break
        }
      }
      assert_eq(finished, success)
      assert_eq(failed, !success)
      if success {
        assert_eq(active.state.control.remaining, 0)
        assert_eq(active.state.keys, [(1, 1)])
        assert_eq(active.state.left_operand, (3, None))
        assert_eq(active.state.right_operand, (2, 0))
        assert_eq(active.state.columns, [(true, 4), (false, 4)])
        // Complete using this fixture's existing independent whole-operation
        // boundary; this is not a production reset or a measured expectation.
        active.state.control.remaining = 14
        let mut result = None
        for _ in 0..<1000 {
          match advance_bounded_interval_join(active, quantum).unwrap() {
            BoundedIntervalJoinContinue(..) => ()
            BoundedIntervalJoinComplete(output, ..) => {
              result = Some(output)
              break
            }
            _ => fail("interval algorithm changed after metadata")
          }
        }
        let output = result.unwrap()
        assert_eq(
          Array::makei(completed_row_count(output), row => {
            completed_output_row_wire(output, row, 1000, 1000, 20).unwrap()
          }),
          compound_port_expected(2),
        )
      }
      assert_true(cleanup_bounded_interval_join(active).unwrap())
      assert_false(cleanup_bounded_interval_join(active).unwrap())
      assert_eq(active.state.workspace.live, 0)
      assert_true(active.state.metadata_lookup is None)
      assert_true(inputs.all(producer_read_available))
    }
    for (work, success) in [(114, true), (113, false)] {
      let (control, active, inputs) = bounded_asof_fixture()
      assert_eq(active.state.control.remaining, 100000)
      assert_true(
        active.state.identities.is_empty() && active.state.columns.is_empty(),
      )
      while !(active.state.phase is ResolveMetadata) {
        assert_true(
          advance_bounded_asof_join(active, 1).unwrap()
          is BoundedAsOfJoinContinue(..),
        )
      }
      // Sorted clock,id,key,priority,value: clocks 12, keys 24,
      // identity 6, tie 36, outputs 6+30 = 114.
      active.state.control.remaining = work
      let mut finished = false
      let mut failed = false
      for _ in 0..<1000 {
        match advance_bounded_asof_join(active, 1).unwrap() {
          BoundedAsOfJoinContinue(..) => ()
          BoundedAsOfJoinFailed(InvalidExecution, ..) => {
            failed = true
            break
          }
          _ => fail("unexpected as-of preparation terminal")
        }
        if active.state.phase is ValidateIdentity {
          finished = true
          break
        }
      }
      assert_eq(finished, success)
      assert_eq(failed, !success)
      if success {
        assert_eq(active.state.control.remaining, 0)
        assert_eq((active.state.left_time, active.state.right_time), (0, 0))
        assert_eq(active.state.keys, [(2, 2)])
        assert_eq(active.state.identities, [1])
        assert_eq(active.state.ties, [3])
        assert_eq(active.state.columns, [(true, 1), (false, 4)])
        assert_true(@bounded.request_cancel(control))
        assert_true(
          advance_bounded_asof_join(active, 1).unwrap()
          is BoundedAsOfJoinStopped(_, ..),
        )
      }
      assert_true(cleanup_bounded_asof_join(active).unwrap())
      assert_false(cleanup_bounded_asof_join(active).unwrap())
      assert_eq(active.state.workspace.live, 0)
      assert_true(active.state.metadata_lookup is None)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "compound metadata cancellation retains inputs and clears cursor reservations once" {
  for kind in [1, 2, 3] {
    for target in [0, 1, 2, 3] {
      if target == 2 && kind != 1 {
        continue
      }
      let (control, active, inputs) = compound_port_fixture(kind, 10000)
      let mut reached = false
      for _ in 0..<10000 {
        assert_true(compound_port_advance(active, 1) is CompoundContinue(_))
        reached = match active {
          CompoundNest(value) =>
            match value.state.metadata_lookup {
              Some(cursor) =>
                cursor.phase == target && (cursor.offset > 0 || target == 3)
              None => false
            }
          CompoundInterval(value) =>
            match value.state.metadata_lookup {
              Some(cursor) =>
                cursor.phase == target && (cursor.offset > 0 || target == 3)
              None => false
            }
          CompoundAsOf(value) =>
            match value.state.metadata_lookup {
              Some(cursor) =>
                cursor.phase == target && (cursor.offset > 0 || target == 3)
              None => false
            }
          _ => false
        }
        // Phase zero pays an entry and advances immediately. Stop there is
        // represented by the next owned cursor with no charged text yet.
        if target == 0 {
          reached = match active {
            CompoundNest(value) =>
              value.state.metadata_lookup is Some(cursor) &&
              cursor.phase == 1 &&
              cursor.offset == 0
            CompoundInterval(value) =>
              value.state.metadata_lookup is Some(cursor) &&
              cursor.phase == 1 &&
              cursor.offset == 0
            CompoundAsOf(value) =>
              value.state.metadata_lookup is Some(cursor) &&
              cursor.phase == 1 &&
              cursor.offset == 0
            _ => false
          }
        }
        if reached {
          break
        }
      }
      assert_true(reached)
      let (remaining, _) = compound_port_totals(active)
      assert_true(inputs.all(producer_read_available))
      assert_true(@bounded.request_cancel(control))
      assert_true(compound_port_advance(active, 1) is CompoundStopped(_))
      assert_eq(compound_port_totals(active).0, remaining)
      assert_true(compound_port_cleanup(active))
      assert_false(compound_port_cleanup(active))
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "Nest borrows long input names and stops within charged source lookup" {
  let name = "x".repeat(256) + "😀é"
  let rename = fn(text : String) {
    text.replace_all(old="\"key\"", new="\"" + name + "\"")
  }
  for (quantum, stop) in [(1, false), (7, false), (256, false), (1, true)] {
    let (control, started, inputs) = bounded_nest_fixture(
      nest=rename(
        "\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}],\"max_items\":3",
      ),
      left_schema=rename(
        "{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true}}",
      ),
      right_schema=rename(
        "{\"key\":{\"type\":\"number\",\"nullable\":true},\"value\":{\"type\":\"number\",\"nullable\":true}}",
      ),
      left_rows=rename("[{\"id\":1,\"key\":1}]"),
      right_rows=rename("[{\"key\":1,\"value\":10}]"),
      max_work=100000,
      max_entries=1000,
      name_bytes=10000,
    )
    let active = started.unwrap()
    assert_eq(active.state.control.remaining, 100000)
    assert_true(active.state.metadata_lookup is None)
    let mut output = None
    let mut reached = false
    for _ in 0..<20000 {
      match advance_bounded_nest(active, quantum).unwrap() {
        BoundedNestContinue(..) => ()
        BoundedNestComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("long-name Nest did not complete")
      }
      if stop &&
        active.state.metadata_lookup is Some(cursor) &&
        cursor.phase == 1 &&
        cursor.offset == 128 {
        reached = true
        break
      }
    }
    if stop {
      assert_true(reached)
      let remaining = active.state.control.remaining
      assert_true(@bounded.request_cancel(control))
      assert_true(
        advance_bounded_nest(active, 1).unwrap() is BoundedNestStopped(_, ..),
      )
      assert_eq(active.state.control.remaining, remaining)
      assert_true(active.state.rows.val is None && !active.state.accepted.val)
      assert_true(cleanup_bounded_nest(active).unwrap())
      assert_eq(active.state.workspace.live, 0)
      assert_true(active.state.metadata_lookup is None)
      assert_true(inputs.all(producer_read_available))
      continue
    }
    let output = output.unwrap()
    assert_true(completed_output_matches_inputs(output, inputs))
    assert_eq(
      Array::makei(completed_row_count(output), row => {
        completed_output_row_wire(output, row, 10000, 1000, 20).unwrap()
      }),
      [rename("{\"id\":1,\"items\":[{\"amount\":10}],\"key\":1}")],
    )
    assert_true(cleanup_bounded_nest(active).unwrap())
    assert_eq(active.state.workspace.live, 0)
    assert_true(inputs.all(producer_read_available))
  }
}
