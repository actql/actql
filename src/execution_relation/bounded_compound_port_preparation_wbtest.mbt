///|
priv enum CompoundPortKernel {
  CompoundJoin(BoundedJoinExecution)
  CompoundNest(BoundedNestExecution)
  CompoundInterval(BoundedIntervalJoinExecution)
  CompoundAsOf(BoundedAsOfJoinExecution)
  CompoundSequence(BoundedSequenceMatchExecution)
}

///|
priv enum CompoundPortPoll {
  CompoundContinue(Int64)
  CompoundComplete(CompletedOutput, Int64)
  CompoundNameLimit(Int64)
  CompoundStopped(Int64)
  CompoundUnexpected
}

///|
/// Real checked and lowered fixtures preserve exact ordered input bindings.
fn compound_port_fixture(
  kind : Int,
  name_bytes : Int,
) -> (@bounded.Control, CompoundPortKernel, Array[ProducerRead]) raise {
  match kind {
    0 => {
      let (control, active, inputs) = bounded_join_fixture(name_bytes~)
      (control, CompoundJoin(active), inputs)
    }
    1 => {
      let (control, active, inputs) = bounded_nest_fixture(
        max_work=100000,
        max_entries=1000,
        name_bytes~,
      )
      (control, CompoundNest(active.unwrap()), inputs)
    }
    2 => {
      let (control, active, inputs) = bounded_interval_fixture_result(
        100000,
        name_bytes~,
      ).unwrap()
      (control, CompoundInterval(active), inputs)
    }
    3 => {
      let (control, active, inputs) = bounded_asof_fixture_result(
        10000,
        100000,
        name_bytes~,
      ).unwrap()
      (control, CompoundAsOf(active), inputs)
    }
    4 => {
      let (control, active, input) = bounded_sequence_try_fixture(name_bytes~)
      (control, CompoundSequence(active.unwrap()), [input])
    }
    _ => fail("unknown compound port fixture")
  }
}

///|
fn compound_port_advance(
  active : CompoundPortKernel,
  quantum : Int,
) -> CompoundPortPoll {
  match active {
    CompoundJoin(value) =>
      match advance_bounded_join(value, quantum).unwrap() {
        BoundedJoinContinue(work~, ..) => CompoundContinue(work)
        BoundedJoinComplete(output, work~, ..) => CompoundComplete(output, work)
        BoundedJoinFailed(Completion(Limit), work~, ..) =>
          CompoundNameLimit(work)
        BoundedJoinStopped(_, work~, ..) => CompoundStopped(work)
        _ => CompoundUnexpected
      }
    CompoundNest(value) =>
      match advance_bounded_nest(value, quantum).unwrap() {
        BoundedNestContinue(work~, ..) => CompoundContinue(work)
        BoundedNestComplete(output, work~, ..) => CompoundComplete(output, work)
        BoundedNestFailed(Completion(Limit), work~, ..) =>
          CompoundNameLimit(work)
        BoundedNestStopped(_, work~, ..) => CompoundStopped(work)
        _ => CompoundUnexpected
      }
    CompoundInterval(value) =>
      match advance_bounded_interval_join(value, quantum).unwrap() {
        BoundedIntervalJoinContinue(work~, ..) => CompoundContinue(work)
        BoundedIntervalJoinComplete(output, work~, ..) =>
          CompoundComplete(output, work)
        BoundedIntervalJoinFailed(Completion(Limit), work~, ..) =>
          CompoundNameLimit(work)
        BoundedIntervalJoinStopped(_, work~, ..) => CompoundStopped(work)
        _ => CompoundUnexpected
      }
    CompoundAsOf(value) =>
      match advance_bounded_asof_join(value, quantum).unwrap() {
        BoundedAsOfJoinContinue(work~, ..) => CompoundContinue(work)
        BoundedAsOfJoinComplete(output, work~, ..) =>
          CompoundComplete(output, work)
        BoundedAsOfJoinFailed(Completion(Limit), work~, ..) =>
          CompoundNameLimit(work)
        BoundedAsOfJoinStopped(_, work~, ..) => CompoundStopped(work)
        _ => CompoundUnexpected
      }
    CompoundSequence(value) =>
      match advance_bounded_sequence_match(value, quantum).unwrap() {
        BoundedSequenceMatchContinue(work~, ..) => CompoundContinue(work)
        BoundedSequenceMatchComplete(output, work~, ..) =>
          CompoundComplete(output, work)
        BoundedSequenceMatchFailed(Completion(Limit), work~, ..) =>
          CompoundNameLimit(work)
        BoundedSequenceMatchStopped(_, work~, ..) => CompoundStopped(work)
        _ => CompoundUnexpected
      }
  }
}

///|
fn compound_port_cursor(
  active : CompoundPortKernel,
) -> TrustedOutputPreparation? {
  match active {
    CompoundJoin(value) => value.state.port_preparation
    CompoundNest(value) => value.state.port_preparation
    CompoundInterval(value) => value.state.port_preparation
    CompoundAsOf(value) => value.state.port_preparation
    CompoundSequence(value) => value.state.port_preparation
  }
}

///|
fn compound_port_totals(active : CompoundPortKernel) -> (Int, Int) {
  match active {
    CompoundJoin(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    CompoundNest(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    CompoundInterval(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    CompoundAsOf(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
    CompoundSequence(value) =>
      (value.state.control.remaining, value.state.workspace.peak)
  }
}

///|
fn compound_port_unpublished(active : CompoundPortKernel) -> Bool {
  match active {
    CompoundJoin(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    CompoundNest(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    CompoundInterval(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    CompoundAsOf(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
    CompoundSequence(value) =>
      value.state.port is None &&
      value.state.rows.val is None &&
      !value.state.accepted.val
  }
}

///|
fn compound_port_cleanup(active : CompoundPortKernel) -> Bool {
  match active {
    CompoundJoin(value) =>
      cleanup_bounded_join(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    CompoundNest(value) =>
      cleanup_bounded_nest(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    CompoundInterval(value) =>
      cleanup_bounded_interval_join(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    CompoundAsOf(value) =>
      cleanup_bounded_asof_join(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
    CompoundSequence(value) =>
      cleanup_bounded_sequence_match(value).unwrap() &&
      value.state.workspace.live == 0 &&
      value.state.output is None &&
      value.state.port_preparation is None
  }
}

///|
/// Targets occur twice, output schema names once. Literal UTF-8 byte counts
/// are independent of provider measurements and successful execution.
fn compound_port_exact_bytes(kind : Int) -> Int {
  match kind {
    0 => 2 * 6 + 1 + 1 + 1
    1 => 2 * 6 + 2 + 3 + 5
    2 => 2 * 15 + 10 + 11
    3 => 2 * 11 + 2 + 7
    4 => 2 * 10 + 3 + 14 + 12 + 8 + 13 + 6 + 11
    _ => -1
  }
}

///|
fn compound_port_expected(kind : Int) -> Array[String] {
  match kind {
    0 => ["{\"k\":1,\"l\":10,\"r\":20}"]
    1 =>
      [
        "{\"id\":1,\"items\":[{\"amount\":null},{\"amount\":10}],\"key\":1}", "{\"id\":2,\"items\":[{\"amount\":null},{\"amount\":10}],\"key\":1}",
        "{\"id\":3,\"items\":[],\"key\":null}", "{\"id\":4,\"items\":[],\"key\":2}",
      ]
    2 =>
      [
        "{\"left_value\":10,\"right_value\":20}", "{\"left_value\":10,\"right_value\":21}",
        "{\"left_value\":11,\"right_value\":null}",
      ]
    3 =>
      [
        "{\"id\":1,\"matched\":300}", "{\"id\":2,\"matched\":300}", "{\"id\":3,\"matched\":null}",
      ]
    4 =>
      [
        "{\"end_id\":2,\"end_time_ms\":2,\"key\":1,\"match_end_ms\":2,\"match_start_ms\":1,\"start_id\":1,\"start_time_ms\":1}",
        "{\"end_id\":3,\"end_time_ms\":3,\"key\":1,\"match_end_ms\":3,\"match_start_ms\":1,\"start_id\":1,\"start_time_ms\":1}",
        "{\"end_id\":4,\"end_time_ms\":4,\"key\":2,\"match_end_ms\":4,\"match_start_ms\":3,\"start_id\":5,\"start_time_ms\":3}",
      ]
    _ => []
  }
}

///|
fn check_compound_port_boundary(kind : Int) -> Unit raise {
  let mut baseline : (Int64, (Int, Int))? = None
  for quantum in [1, 7, 256] {
    for short in [false, true] {
      let (_, active, inputs) = compound_port_fixture(
        kind,
        compound_port_exact_bytes(kind) - (if short { 1 } else { 0 }),
      )
      assert_true(compound_port_cursor(active) is Some(_))
      assert_true(compound_port_unpublished(active))
      let mut terminal = false
      let mut previous = 0L
      for _ in 0..<10000 {
        if !terminal {
          match compound_port_advance(active, quantum) {
            CompoundContinue(work) => {
              assert_true(
                work > previous && work - previous <= quantum.to_int64(),
              )
              previous = work
            }
            CompoundComplete(output, work) => {
              assert_false(short)
              assert_true(work - previous <= quantum.to_int64())
              assert_true(completed_output_matches_inputs(output, inputs))
              let actual = Array::makei(completed_row_count(output), row => {
                completed_output_row_wire(output, row, 1000, 1000, 20).unwrap()
              })
              assert_eq(actual, compound_port_expected(kind))
              let totals = (work, compound_port_totals(active))
              if baseline is Some(expected) {
                assert_eq(totals, expected)
              } else {
                baseline = Some(totals)
              }
              assert_true(compound_port_cleanup(active))
              assert_false(compound_port_cleanup(active))
              assert_true(completed_output_available(output))
              terminal = true
            }
            CompoundNameLimit(work) => {
              assert_true(short)
              assert_true(work - previous <= quantum.to_int64())
              assert_true(compound_port_unpublished(active))
              assert_true(compound_port_cleanup(active))
              assert_false(compound_port_cleanup(active))
              terminal = true
            }
            _ => fail("unexpected compound completion outcome")
          }
        }
      }
      assert_true(terminal)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "bounded compound join completion preparation has exact bytes and quantum-independent work" {
  check_compound_port_boundary(0)
}

///|
test "bounded compound nest completion preparation has exact bytes and quantum-independent work" {
  check_compound_port_boundary(1)
}

///|
test "bounded compound interval completion preparation has exact bytes and quantum-independent work" {
  check_compound_port_boundary(2)
}

///|
test "bounded compound asof completion preparation has exact bytes and quantum-independent work" {
  check_compound_port_boundary(3)
}

///|
test "bounded compound sequence completion preparation has exact bytes and quantum-independent work" {
  check_compound_port_boundary(4)
}

///|
test "bounded compound completion preparation cancels inside every name phase" {
  for kind in 0..<5 {
    for phase in 0..<4 {
      let (control, active, inputs) = compound_port_fixture(
        kind,
        compound_port_exact_bytes(kind),
      )
      let mut reached = false
      for _ in 0..<300 {
        if !reached {
          let cursor = compound_port_cursor(active).unwrap()
          if cursor.phase == phase && cursor.offset > 0 {
            reached = true
          } else {
            assert_true(compound_port_advance(active, 1) is CompoundContinue(_))
          }
        }
      }
      assert_true(reached)
      assert_true(compound_port_unpublished(active))
      let cursor = compound_port_cursor(active).unwrap()
      let totals = compound_port_totals(active)
      assert_true(@bounded.request_cancel(control))
      assert_true(
        compound_port_advance(active, 1) is CompoundStopped(work) && work > 0L,
      )
      assert_true(compound_port_unpublished(active))
      assert_true(inputs.all(producer_read_available))
      assert_true(compound_port_cleanup(active))
      assert_false(compound_port_cleanup(active))
      assert_true(cursor.closed)
      assert_eq(cursor.names.length(), 0)
      assert_eq(compound_port_totals(active), totals)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "bounded compound completion preparation preserves long Unicode schema names" {
  let name = "é😀".repeat(32)
  // Two six-byte targets, k and l, then 32 two-plus-four-byte pairs.
  let exact = 2 * 6 + 1 + 1 + 32 * (2 + 4)
  let mut baseline : (Int64, (Int, Int))? = None
  for quantum in [1, 7, 256] {
    for short in [false, true] {
      let (_, execution, inputs) = bounded_join_fixture(
        name_bytes=exact - (if short { 1 } else { 0 }),
        right_name=name,
      )
      let active = CompoundJoin(execution)
      let mut terminal = false
      let mut previous = 0L
      for _ in 0..<2000 {
        if !terminal {
          match compound_port_advance(active, quantum) {
            CompoundContinue(work) => {
              assert_true(
                work > previous && work - previous <= quantum.to_int64(),
              )
              previous = work
            }
            CompoundComplete(output, work) => {
              assert_false(short)
              assert_eq(completed_column_name(output, 2), Some(name))
              assert_eq(completed_row_count(output), 1)
              assert_eq(
                completed_output_row_wire(output, 0, 1000, 1000, 20).unwrap(),
                "{\"k\":1,\"l\":10,\"" + name + "\":20}",
              )
              let totals = (work, compound_port_totals(active))
              if baseline is Some(expected) {
                assert_eq(totals, expected)
              } else {
                baseline = Some(totals)
              }
              assert_true(compound_port_cleanup(active))
              assert_eq(completed_column_name(output, 2), Some(name))
              assert_true(completed_output_available(output))
              terminal = true
            }
            CompoundNameLimit(_) => {
              assert_true(short)
              assert_true(compound_port_unpublished(active))
              assert_true(compound_port_cleanup(active))
              terminal = true
            }
            _ => fail("Unicode compound completion ended unexpectedly")
          }
        }
      }
      assert_true(terminal)
      assert_true(inputs.all(producer_read_available))
    }
  }
}
