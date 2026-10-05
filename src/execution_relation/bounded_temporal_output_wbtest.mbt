///|
priv enum TemporalOutputFixture {
  Interval(BoundedIntervalJoinExecution)
  AsOf(BoundedAsOfJoinExecution)
  Sequence(BoundedSequenceMatchExecution)
}

///|
priv enum TemporalOutputPoll {
  Continue
  Complete(CompletedOutput)
  Stopped
  OutputLimit
  WorkspaceLimit
}

///|
fn temporal_output_source(
  rows : String,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{" +
    "\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"key\":{\"type\":\"number\",\"nullable\":false}," +
    "\"clock\":{\"type\":\"number\",\"nullable\":false}," +
    "\"start\":{\"type\":\"number\",\"nullable\":false}," +
    "\"end\":{\"type\":\"number\",\"nullable\":false}," +
    "\"tag\":{\"type\":\"string\",\"nullable\":false}}," +
    "\"rows\":" +
    rows +
    "},\"as\":\"source\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], compute_test_limits()).unwrap()
  (owner, completed_output(result, @pipeline.Step(0)).unwrap())
}

///|
fn temporal_output_fixture(
  kind : Int,
  limits : ValueLimits,
  max_entries? : Int = 100,
) -> (@bounded.Control, TemporalOutputFixture, Array[ProducerRead]) raise {
  let rows = "[{\"id\":1,\"key\":1,\"clock\":1,\"start\":0,\"end\":5,\"tag\":\"" +
    "x".repeat(4096) +
    "\"}" +
    (if kind == 2 {
      ",{\"id\":2,\"key\":1,\"clock\":2,\"start\":0,\"end\":5,\"tag\":\"end\"}]"
    } else {
      "]"
    })
  let (left_owner, left_output) = temporal_output_source(rows)
  let (right_owner, right_output) = temporal_output_source(
    "[{\"id\":2,\"key\":1,\"clock\":1,\"start\":0,\"end\":5,\"tag\":\"right\"}]",
  )
  let left_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(left_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let right_producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(right_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let operation = if kind == 0 {
    "\"interval_join\":{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\"," +
    "\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"left\":{\"time\":\"clock\"}," +
    "\"right\":{\"start\":\"start\",\"end\":\"end\"}," +
    "\"select\":{\"id\":\"left.id\",\"tag\":\"left.tag\"}}"
  } else if kind == 1 {
    "\"asof_join\":{\"with\":\"r\",\"kind\":\"left\"," +
    "\"by\":[{\"left\":\"key\",\"right\":\"key\"}],\"left_id\":\"id\"," +
    "\"left_time\":\"clock\",\"right_time\":\"clock\",\"direction\":\"backward\"," +
    "\"tolerance\":20,\"right_tie_break\":[\"id\"]," +
    "\"select\":{\"id\":\"left.id\",\"tag\":\"left.tag\"}}"
  } else {
    "\"sequence\":{\"by\":[\"key\"],\"id\":\"tag\",\"time\":\"clock\"," +
    "\"pattern\":[{\"as\":\"start\",\"where\":\"id = 1\"},{\"as\":\"end\",\"where\":\"id = 2\"}]," +
    "\"within\":10,\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}"
  }
  let inputs = [("l", @pipeline.ProducedInput(left_producer))]
  if kind != 2 {
    inputs.push(("r", @pipeline.ProducedInput(right_producer)))
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"l\"," + operation + "}]"),
    inputs,
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [
      if kind == 0 {
        "interval_join_0"
      } else if kind == 1 {
        "asof_join_0"
      } else {
        "sequence_0"
      },
    ],
    100000,
    10000,
  ).unwrap()
  let left = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, left_owner, left_output).unwrap(),
    100,
    10000,
  ).unwrap()
  let generated = if kind == 0 {
    constrain_generated_join_output(
      constrain_generated_interval_search(generated, 0, 1L).unwrap(),
      0,
      1L,
    ).unwrap()
  } else if kind == 1 {
    constrain_generated_join_output(
      constrain_generated_asof_search(generated, 0, 1L).unwrap(),
      0,
      1L,
    ).unwrap()
  } else {
    generated
  }
  let reads = [left]
  let control = @bounded.control()
  let active = if kind == 2 {
    Sequence(
      start_bounded_sequence_match(
        control, generated, left, 10, limits, 100000, 100, max_entries, 10000,
      ).unwrap(),
    )
  } else {
    let right = prepare_producer_read(
      receiver,
      bind_completed_input(receiver, 1, right_owner, right_output).unwrap(),
      100,
      10000,
    ).unwrap()
    reads.push(right)
    if kind == 0 {
      Interval(
        start_bounded_interval_join(
          control, generated, left, right, 10, limits, 100000, 100, max_entries,
          10000,
        ).unwrap(),
      )
    } else {
      AsOf(
        start_bounded_asof_join(
          control, generated, left, right, 10, limits, 100000, 100, max_entries,
          10000,
        ).unwrap(),
      )
    }
  }
  (control, active, reads)
}

///|
fn temporal_output_limits(kind : Int) -> ValueLimits {
  // Join: outer row, two cells, id/tag names (five bytes), 4096 Text bytes.
  // Sequence: outer row, seven cells, 67 name bytes and 4099 Text bytes.
  let (nodes, bytes) = if kind == 2 { (8, 4166) } else { (3, 4101) }
  {
    max_nodes: nodes,
    max_text_bytes: bytes,
    max_depth: 2,
    max_work: nodes + bytes,
  }
}

///|
fn advance_temporal_output(
  value : TemporalOutputFixture,
) -> TemporalOutputPoll raise {
  match value {
    Interval(value) =>
      match advance_bounded_interval_join(value, 1).unwrap() {
        BoundedIntervalJoinContinue(..) => Continue
        BoundedIntervalJoinComplete(output, ..) => Complete(output)
        BoundedIntervalJoinStopped(_, ..) => Stopped
        BoundedIntervalJoinFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedIntervalJoinFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("unexpected interval output failure")
      }
    AsOf(value) =>
      match advance_bounded_asof_join(value, 1).unwrap() {
        BoundedAsOfJoinContinue(..) => Continue
        BoundedAsOfJoinComplete(output, ..) => Complete(output)
        BoundedAsOfJoinStopped(_, ..) => Stopped
        BoundedAsOfJoinFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedAsOfJoinFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("unexpected as-of output failure")
      }
    Sequence(value) =>
      match advance_bounded_sequence_match(value, 1).unwrap() {
        BoundedSequenceMatchContinue(..) => Continue
        BoundedSequenceMatchComplete(output, ..) => Complete(output)
        BoundedSequenceMatchStopped(_, ..) => Stopped
        BoundedSequenceMatchFailed(Capture(CaptureLimit), ..) => OutputLimit
        BoundedSequenceMatchFailed(Rows(RowLimit), ..) => WorkspaceLimit
        _ => fail("unexpected sequence output failure")
      }
  }
}

///|
fn temporal_output_inside(
  value : TemporalOutputFixture,
  charging : Bool,
) -> Bool {
  match value {
    Interval(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
    AsOf(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
    Sequence(value) =>
      if charging {
        value.state.output_charge is Some(cursor) && cursor.measure is Some(_)
      } else {
        value.state.output_recheck is Some(_)
      }
  }
}

///|
fn cleanup_temporal_output(value : TemporalOutputFixture) -> Unit raise {
  match value {
    Interval(value) => {
      assert_true(cleanup_bounded_interval_join(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
    AsOf(value) => {
      assert_true(cleanup_bounded_asof_join(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
    Sequence(value) => {
      assert_true(cleanup_bounded_sequence_match(value).unwrap())
      assert_eq(value.state.workspace.live, 0)
      assert_true(value.state.output_recheck is None)
      assert_true(value.state.output_charge is None)
      assert_true(value.state.checked_row.is_empty())
      if !value.accepted.val {
        assert_true(value.state.rows.val is None)
      }
    }
  }
}

///|
fn assert_temporal_output(output : CompletedOutput, kind : Int) -> Unit raise {
  let names = if kind == 2 {
    [
      "end_id", "end_time_ms", "key", "match_end_ms", "match_start_ms", "start_id",
      "start_time_ms",
    ]
  } else {
    ["id", "tag"]
  }
  assert_eq(completed_row_count(output), 1)
  assert_eq(completed_column_count(output), names.length())
  for index in 0..<names.length() {
    let name = names[index]
    assert_eq(completed_column_name(output, index), Some(name))
    let cell = completed_cell(output, 0, index)
    if name == "tag" || name == "start_id" {
      assert_true(cell is Some(Text(text)) && text == "x".repeat(4096))
    } else if name == "end_id" {
      assert_true(cell is Some(Text("end")))
    } else if name == "end_time_ms" || name == "match_end_ms" {
      assert_true(cell is Some(Number(2.0)))
    } else {
      assert_true(cell is Some(Number(1.0)))
    }
  }
}

///|
test "temporal output keeps exact node byte and work limits" {
  for kind in 0..<3 {
    for short in -1..<3 {
      let exact = temporal_output_limits(kind)
      let limits = {
        max_nodes: exact.max_nodes - (if short == 0 { 1 } else { 0 }),
        max_text_bytes: exact.max_text_bytes - (if short == 1 { 1 } else { 0 }),
        max_depth: exact.max_depth,
        max_work: exact.max_work - (if short == 2 { 1 } else { 0 }),
      }
      let (_, active, inputs) = temporal_output_fixture(kind, limits)
      let mut terminal = false
      for _ in 0..<30000 {
        match advance_temporal_output(active) {
          Continue => ()
          Complete(output) => {
            assert_eq(short, -1)
            assert_temporal_output(output, kind)
            terminal = true
            break
          }
          OutputLimit => {
            assert_true(short >= 0)
            terminal = true
            break
          }
          _ => fail("unexpected temporal output boundary failure")
        }
      }
      assert_true(terminal)
      cleanup_temporal_output(active)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "temporal output stops inside recheck and charge with live inputs" {
  for kind in 0..<3 {
    for charging in [false, true] {
      let (control, active, inputs) = temporal_output_fixture(
        kind,
        temporal_output_limits(kind),
      )
      let mut reached = false
      for _ in 0..<30000 {
        assert_true(advance_temporal_output(active) is Continue)
        if temporal_output_inside(active, charging) {
          reached = true
          break
        }
      }
      assert_true(reached)
      // Execute an actual Text chunk before delivering cancellation.
      assert_true(advance_temporal_output(active) is Continue)
      assert_true(temporal_output_inside(active, charging))
      assert_true(inputs.all(producer_read_available))
      assert_true(@bounded.request_cancel(control))
      assert_true(advance_temporal_output(active) is Stopped)
      cleanup_temporal_output(active)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "temporal output reserves traversal workspace before measurement" {
  // Interval: ten metadata + two raw + two checked + one traversal frame.
  // As-of: ten metadata + one ordered index + the same five output slots.
  // Identity-sort indexes have already been released before output begins.
  // Sequence: 22 metadata + two indexes + three match slots + 15 row slots
  // and one traversal frame. These formulas do not use observed peaks.
  for kind in 0..<3 {
    let required = if kind == 0 { 15 } else if kind == 1 { 16 } else { 43 }
    for short in [false, true] {
      let (_, active, inputs) = temporal_output_fixture(
        kind,
        temporal_output_limits(kind),
        max_entries=required - (if short { 1 } else { 0 }),
      )
      let mut terminal = false
      for _ in 0..<30000 {
        match advance_temporal_output(active) {
          Continue => ()
          Complete(output) => {
            assert_false(short)
            assert_temporal_output(output, kind)
            terminal = true
            break
          }
          WorkspaceLimit => {
            assert_true(short)
            terminal = true
            break
          }
          _ => fail("unexpected traversal workspace failure")
        }
      }
      assert_true(terminal)
      cleanup_temporal_output(active)
      assert_true(inputs.all(producer_read_available))
    }
  }
}

///|
test "sequence output resolution yields between key and pattern probes" {
  for pattern_phase in [false, true] {
    let (control, active, inputs) = temporal_output_fixture(
      2,
      temporal_output_limits(2),
    )
    guard active is Sequence(value) else { fail("expected sequence execution") }
    let mut reached = false
    for _ in 0..<30000 {
      assert_true(advance_temporal_output(active) is Continue)
      if (if pattern_phase {
          value.state.phase is ResolveOutputPattern
        } else {
          value.state.phase is ResolveOutputKey
        }) {
        reached = true
        break
      }
    }
    assert_true(reached)
    let column = value.state.output_column
    let key = value.state.output_key
    let pattern = value.state.output_pattern
    assert_true(advance_temporal_output(active) is Continue)
    assert_true(value.state.output_column <= column + 1)
    assert_true(value.state.output_key <= key + 1)
    assert_true(value.state.output_pattern <= pattern + 1)
    assert_true(@bounded.request_cancel(control))
    assert_true(advance_temporal_output(active) is Stopped)
    cleanup_temporal_output(active)
    assert_true(inputs.all(producer_read_available))
  }
}
