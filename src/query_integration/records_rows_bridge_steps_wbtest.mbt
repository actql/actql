///|
fn large_records_projection_input() -> (
  @execution.CompletedOutput,
  @records.Completed,
  @lower.BoundPrepared,
  @records.ProducerRead,
) raise {
  let (source, events_owner, input) = large_rows_events_bridge_input()
  let encoding = @local_bridge.start_rows_to_events(
    @bounded.control(),
    prepared_sequence(events_owner),
    0,
    input,
    large_rows_events_bridge_limits(149, 71),
    10000L,
    fn() { true },
  ).unwrap()
  let events = finish_rows_to_events(encoding)
  assert_eq(@local_bridge.cleanup_rows_to_events(encoding), Ok(true))
  let owner = carrier_events_projection_owner(events_owner)
  let input = @records.prepare_producer_read(owner, 0, events_owner, events).unwrap()
  (source, events, owner, input)
}

///|
fn named_records_projection_input() -> (
  @execution.CompletedOutput,
  @records.Completed,
  @lower.BoundPrepared,
  @records.ProducerRead,
) raise {
  let name = String::make(513, 'z')
  let source_owner = local_managed_support_owner(
    "[{\"values\":{\"schema\":{" +
    "\"event_id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"occurred_at\":{\"type\":\"number\",\"nullable\":false}," +
    "\"payload\":{\"type\":\"number\",\"nullable\":false},\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":false}}," +
    "\"rows\":[{\"event_id\":1,\"occurred_at\":12,\"payload\":7,\"" +
    name +
    "\":9}]},\"as\":\"source\"}]",
  )
  let source = carrier_events_source_output(source_owner)
  let events_owner = carrier_events_output_owner(source_owner)
  let input = @execution.prepare_producer_read(
    events_owner,
    @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
    100,
    2000,
  ).unwrap()
  let encoding = @local_bridge.start_rows_to_events(
    @bounded.control(),
    prepared_sequence(events_owner),
    0,
    input,
    carrier_events_storage_limits(),
    10000L,
    fn() { true },
  ).unwrap()
  let events = finish_rows_to_events(encoding)
  assert_eq(@local_bridge.cleanup_rows_to_events(encoding), Ok(true))
  let owner = carrier_events_projection_owner(events_owner)
  let read = @records.prepare_producer_read(owner, 0, events_owner, events).unwrap()
  (source, events, owner, read)
}

///|
test "record projection fragments name matching without hashing pending fields" {
  let (source, events, owner, input) = named_records_projection_input()
  // Four init/source/verify polls, sixteen binary comparison polls, one
  // start and 31 row polls = 60. Long-name comparison and output charge
  // each scan nine fragments. Logical output: five nodes + 539 name bytes.
  // Workspace: four matched cells + thirteen custody slots + five row
  // slots + one name-measure frame = 23.
  for
    (work, workspace, outcome, quantum) in [
      (60, 23, "complete", 1),
      (60, 23, "complete", 7),
      (60, 23, "complete", 256),
      (59, 23, "work", 1),
      (60, 22, "workspace", 1),
    ] {
    let active = @local_bridge.start_events_view_to_rows(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      @records.producer_read_view(input).unwrap(),
      1,
      { max_nodes: 5, max_text_bytes: 539, max_depth: 10, max_work: 544, },
      workspace,
      1000,
      control_work_limit=Some(work),
    ).unwrap()
    let mut terminal = false
    let mut prior = 0L
    for _ in 0..<70 {
      match @local_bridge.advance_events_to_rows(active, quantum).unwrap() {
        @local_bridge.Continue(progress~, work~) => {
          assert_true(work > prior && work - prior <= quantum.to_int64())
          assert_true(progress == 0L || work == 60L)
          prior = work
        }
        @local_bridge.Complete(output, work~, ..) => {
          assert_eq(outcome, "complete")
          assert_eq(work, 60L)
          for (column, expected) in [(0, 1.0), (1, 12.0), (2, 7.0), (3, 9.0)] {
            assert_true(
              @execution.completed_cell(output, 0, column)
              is Some(Number(value)) &&
              value == expected,
            )
          }
          assert_eq(
            @execution.completed_column_name(output, 3),
            Some(String::make(513, 'z')),
          )
          terminal = true
          break
        }
        @local_bridge.Failed(@local_bridge.ControlWorkLimit, work~, ..) => {
          assert_eq(outcome, "work")
          assert_eq(work, 59L)
          terminal = true
          break
        }
        @local_bridge.Failed(
          @local_bridge.RelationOutput(@execution.CaptureLimit),
          ..
        ) => {
          assert_eq(outcome, "workspace")
          terminal = true
          break
        }
        _ => fail("unexpected named projection terminal")
      }
    }
    assert_true(terminal)
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(true))
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(false))
    assert_true(@records.completed_available(events))
  }
  for boundary in [16, 50] {
    let control = @bounded.control()
    let active = @local_bridge.start_events_view_to_rows(
      control,
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      @records.producer_read_view(input).unwrap(),
      1,
      { max_nodes: 5, max_text_bytes: 539, max_depth: 10, max_work: 544, },
      23,
      1000,
      control_work_limit=Some(60),
    ).unwrap()
    for _ in 0..<boundary {
      guard @local_bridge.advance_events_to_rows(active, 1).unwrap()
        is @local_bridge.Continue(progress~, ..) else {
        fail("named projection missed its fragment boundary")
      }
      assert_eq(progress, 0L)
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(@records.producer_read_available(input))
    guard @local_bridge.advance_events_to_rows(active, 1).unwrap()
      is @local_bridge.Stopped(_, progress~, work~) else {
      fail("named projection did not stop")
    }
    assert_eq(progress, 0L)
    assert_eq(work, boundary.to_int64())
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(true))
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(false))
    assert_true(@records.completed_available(events))
  }
  assert_true(@records.discard_completed(events))
  assert_true(@execution.completed_output_available(source))
}

///|
test "record projection preserves logical limits across stepped values" {
  let (source, events, owner, input) = large_records_projection_input()
  // Four init/source/verify polls, eight binary probes, one cursor start
  // = 21. Recheck loads 400; charge start is one; names/scalars/commit
  // cost seven, long Text 131 and Array 260: total 820.
  // Logical output is outer row 1 + 133 value nodes, and 35 name bytes
  // + 8193 payload bytes: work 134+8228=8362. Caller custody is 4+13,
  // row scope five, Array measurement peaks at two frames: workspace 24.
  for
    (control, logical, workspace, outcome, quantum) in [
      (820, 8362, 24, "complete", 1),
      (820, 8362, 24, "complete", 7),
      (820, 8362, 24, "complete", 256),
      (819, 8362, 24, "control", 1),
      (820, 8361, 24, "logical", 1),
      (820, 8362, 23, "workspace", 1),
    ] {
    let active = @local_bridge.start_events_view_to_rows(
      @bounded.control(),
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      @records.producer_read_view(input).unwrap(),
      1,
      {
        max_nodes: 134,
        max_text_bytes: 8228,
        max_depth: 10,
        max_work: logical,
      },
      workspace,
      1000,
      control_work_limit=Some(control),
    ).unwrap()
    let mut prior = 0L
    let mut terminal = false
    for _ in 0..<900 {
      match @local_bridge.advance_events_to_rows(active, quantum).unwrap() {
        @local_bridge.Continue(work~, progress~) => {
          assert_true(work > prior && work - prior <= quantum.to_int64())
          assert_true(progress == 0L || work == 820L)
          prior = work
        }
        @local_bridge.Complete(output, work~, ..) => {
          assert_eq(outcome, "complete")
          assert_eq(work, 820L)
          assert_eq(@execution.completed_row_count(output), 1)
          assert_true(
            @execution.completed_cell(output, 0, 0) is Some(Number(1.0)),
          )
          assert_true(
            @execution.completed_cell(output, 0, 1) is Some(Number(12.0)),
          )
          assert_true(
            @execution.completed_cell(output, 0, 2) is Some(Text(text)) &&
            text == String::make(8193, 'p'),
          )
          assert_true(
            @execution.completed_cell(output, 0, 3)
            is Some(Captured(@admitted.Array(items))) &&
            @admitted.element_count(items) == 129,
          )
          terminal = true
          break
        }
        @local_bridge.Failed(@local_bridge.ControlWorkLimit, work~, ..) => {
          assert_eq(outcome, "control")
          assert_eq(work, 819L)
          terminal = true
          break
        }
        @local_bridge.Failed(
          @local_bridge.RelationOutput(@execution.CaptureLimit),
          ..
        ) => {
          assert_true(outcome == "logical" || outcome == "workspace")
          terminal = true
          break
        }
        _ => fail("unexpected record projection terminal")
      }
    }
    assert_true(terminal)
    assert_true(@local_bridge.events_to_rows_cleanup_pending(active))
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(true))
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(false))
    assert_true(@records.completed_available(events))
    assert_true(@records.producer_read_available(input))
    assert_true(@execution.completed_output_available(source))
  }
  assert_true(@records.discard_completed(events))
}

///|
test "record projection keeps input through stopped recheck and measurement" {
  let (source, events, owner, input) = large_records_projection_input()
  // Projection setup costs 21. Text recheck starts after six scalar polls;
  // Array recheck follows 132 Text polls. Logical Text/Array measurement
  // starts at polls 429/561 respectively. Total 820 fixes these positions.
  for boundary in [32, 256, 500, 768] {
    let control = @bounded.control()
    let active = @local_bridge.start_events_view_to_rows(
      control,
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      @records.producer_read_view(input).unwrap(),
      1,
      { max_nodes: 134, max_text_bytes: 8228, max_depth: 10, max_work: 8362, },
      24,
      1000,
      control_work_limit=Some(820),
    ).unwrap()
    for _ in 0..<boundary {
      guard @local_bridge.advance_events_to_rows(active, 1).unwrap()
        is @local_bridge.Continue(work~, progress~) else {
        fail("projection completed before cancellation coordinate")
      }
      assert_eq(progress, 0L)
      assert_true(work <= boundary.to_int64())
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(@records.producer_read_available(input))
    guard @local_bridge.advance_events_to_rows(active, 1).unwrap()
      is @local_bridge.Stopped(_, work~, progress~) else {
      fail("projection did not confirm stop")
    }
    assert_eq(work, boundary.to_int64())
    assert_eq(progress, 0L)
    assert_true(@local_bridge.events_to_rows_cleanup_pending(active))
    assert_true(@records.producer_read_available(input))
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(true))
    assert_eq(@local_bridge.cleanup_events_to_rows(active), Ok(false))
    assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
    assert_true(@records.completed_available(events))
    assert_true(@execution.completed_output_available(source))
  }
  assert_true(@records.discard_completed(events))
}
