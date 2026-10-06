///|
fn name_matching_producer(clock : String) -> @lower.BoundPrepared {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let rows = @carrier.rows(
    [
      (@schema.Unqualified("event_id"), Some(number)),
      (@schema.Unqualified(clock), Some(number)),
      (
        @schema.Unqualified("payload"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=3,
    max_name_bytes=clock.length() + 15,
  ).unwrap()
  bind(
    @pipeline.check_carriers(
      cursor(
        "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"" +
        clock +
        "\"}}]",
      ),
      [("rows", @carrier.relation(rows))],
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
    ).unwrap(),
  )
}

///|
fn name_matching_source(
  producer : @lower.BoundPrepared,
  clock : String,
) -> @records.Completed {
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  @records.append_record(builder, [
    (@schema.Unqualified("event_id"), number(1.0)),
    (@schema.Unqualified(clock), number(0.0)),
    (@schema.Unqualified("payload"), text("a")),
  ]).unwrap()
  @records.finish_output(builder).unwrap()
}

///|
fn name_matching_offset(fixture : EmissionFixture) -> Int {
  match fixture {
    Watermark(value) => value.state.name_offset
    Window(value) => value.state.name_offset
    Dedupe(value) => value.state.name_offset
    Session(value) => value.state.name_offset
  }
}

///|
test "Events input names use independent fragment work and workspace limits" {
  // A 513-unit clock takes nine fragments: eight extra input-binding polls.
  // Append scans its hash, schema match, required hash/match and wire name:
  // five passes add 5*8 polls. The short-name primitive baselines are
  // watermark 53, fixed window 53, dedupe 59 and session 90.
  // Workspace adds one persistent position to the prior append peaks.
  let clock = String::make(513, 'a')
  let producer = name_matching_producer(clock)
  let source = name_matching_source(producer, clock)
  for
    (kind, work, slots) in [
      (0, 101, 81),
      (1, 101, 80),
      (2, 107, 71),
      (3, 138, 91),
    ] {
    for quantum in [1, 7, 256] {
      for
        (budget, capacity, accepted) in [
          (work, slots, true),
          (work - 1, slots, false),
          (work, slots - 1, false),
        ] {
        let (fixture, input) = emission_start(
          kind,
          producer,
          source,
          @bounded.control(),
          capacity,
          budget,
          clock~,
        )
        let mut prior = 0L
        let mut terminal = false
        for _ in 0..<200 {
          if terminal {
            break
          }
          match emission_advance(fixture, quantum) {
            Continue(charged) => {
              assert_true(
                charged > prior && charged - prior <= quantum.to_int64(),
              )
              prior = charged
            }
            Complete(output, charged) => {
              assert_true(accepted)
              assert_eq(charged, work.to_int64())
              let storage = @records.completed_storage(output).unwrap()
              assert_eq(@storage.record_count(storage), 1)
              assert_eq(event_window_field(storage, 0, clock), 0.0)
              assert_eq(event_window_field(storage, 0, "event_id"), 1.0)
              assert_eq(session_text_field(storage, 0, "payload"), "a")
              if kind == 0 {
                assert_eq(event_window_field(storage, 0, "watermark_ms"), 10.0)
              } else if kind == 1 {
                assert_eq(
                  event_window_field(storage, 0, "window_start_ms"),
                  0.0,
                )
                assert_eq(event_window_field(storage, 0, "window_end_ms"), 10.0)
              } else if kind == 3 {
                assert_eq(
                  session_text_field(storage, 0, "session_id"),
                  "session:0:v:1:1:v:1:1",
                )
              }
              assert_true(@records.discard_completed(output))
              terminal = true
            }
            WorkLimit(charged) => {
              assert_false(accepted)
              assert_eq(budget, work - 1)
              assert_eq(charged, budget.to_int64())
              terminal = true
            }
            WorkspaceLimit => {
              assert_false(accepted)
              assert_eq(capacity, slots - 1)
              terminal = true
            }
            _ => fail("unexpected Events name-binding outcome")
          }
        }
        assert_true(terminal)
        assert_true(emission_cleanup(fixture))
        assert_false(emission_cleanup(fixture))
        assert_eq(name_matching_offset(fixture), 0)
        assert_true(@records.producer_read_available(input))
      }
    }
  }
  assert_true(@records.discard_completed(source))
}

///|
test "Events input-name cancellation retains pending fields until cleanup" {
  let clock = String::make(513, 'a')
  let producer = name_matching_producer(clock)
  let source = name_matching_source(producer, clock)
  for kind in 0..<4 {
    let control = @bounded.control()
    let (fixture, input) = emission_start(
      kind,
      producer,
      source,
      control,
      1000,
      1000,
      clock~,
    )
    let mut charged = 0L
    for _ in 0..<100 {
      if name_matching_offset(fixture) > 0 {
        break
      }
      match emission_advance(fixture, 1) {
        Continue(work) => charged = work
        _ => fail("must yield inside the input-name comparison")
      }
    }
    assert_eq(name_matching_offset(fixture), 64)
    assert_false(emission_append_active(fixture))
    let output = emission_output(fixture).unwrap()
    let custody = @records.output_workspace_slots(output)
    assert_true(@bounded.request_cancel(control))
    assert_eq(name_matching_offset(fixture), 64)
    assert_true(@records.producer_read_available(input))
    match emission_advance(fixture, 1) {
      Stopped(work) => assert_eq(work, charged)
      _ => fail("pending name comparison must stop without more work")
    }
    assert_eq(name_matching_offset(fixture), 64)
    assert_eq(@records.output_workspace_slots(output), custody)
    assert_true(emission_cleanup(fixture))
    assert_false(emission_cleanup(fixture))
    assert_eq(name_matching_offset(fixture), 0)
    assert_true(emission_output(fixture) is None)
    assert_eq(@records.output_workspace_slots(output), 0)
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}

///|
test "Events name fragments preserve qualification and exact value spelling" {
  assert_eq(
    event_name_equal(
      @schema.Unqualified("left.a"),
      @schema.Qualified(@schema.Left, "a"),
      0,
    ),
    (Some(true), 0),
  )
  assert_eq(
    event_name_equal(@schema.Unqualified("é"), @schema.Unqualified("é"), 0),
    (Some(false), 0),
  )
  let prefix = String::make(128, 'a')
  let a = @schema.Unqualified(prefix + "b")
  let b = @schema.Unqualified(prefix + "c")
  assert_eq(event_name_equal(a, b, 0), (None, 64))
  assert_eq(event_name_equal(a, b, 64), (None, 128))
  assert_eq(event_name_equal(a, b, 128), (Some(false), 0))
}

///|
test "Events session Host quantum ends inside a clock name before emission" {
  let clock = String::make(65, 'a')
  let producer = name_matching_producer(clock)
  let admitted = {
    ..limits(workspace=10000, max_input_records=31),
    max_records: 31,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_work: 10000,
  }
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    admitted,
    100000L,
    fn() { true },
  ).unwrap()
  for row in 1..<32 {
    @records.append_record(builder, [
      (@schema.Unqualified(clock), number(12.0)),
      (@schema.Unqualified("event_id"), number(row.to_double())),
      (@schema.Unqualified("payload"), text("a")),
    ]).unwrap()
  }
  let source = @records.finish_output(builder).unwrap()
  let owner = session_owner(producer, "[\"event_id\"]")
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_session(
    control,
    sequence(owner),
    0,
    input,
    admitted,
    100000L,
    fn() { true },
  ).unwrap()
  // 3*31 cells + one transition + 31 record indices + one transition = 126.
  // Each record: LoadBegin(1), three fields and terms(13), end/verify(4).
  // The clock starts at 130+18*record. Poll 256 is record seven's first
  // 64-unit fragment, before its clock is bound and before any emission.
  assert_true(
    advance_session(execution, 256).unwrap()
    is SessionContinue(work=256L, progress=0L),
  )
  assert_eq(execution.state.record, 7)
  assert_true(execution.state.phase is LoadTerm)
  assert_eq(execution.state.name_offset, 64)
  assert_true(
    execution.state.cells[7 * execution.state.terms + execution.state.keys]
    is None,
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_session(execution, 1).unwrap()
    is SessionStopped(_, work=256L, progress=0L),
  )
  assert_eq(execution.state.name_offset, 64)
  assert_true(@records.producer_read_available(input))
  assert_true(cleanup_session(execution).unwrap())
  assert_false(cleanup_session(execution).unwrap())
  assert_eq(execution.state.name_offset, 0)
  assert_true(@records.producer_read_available(input))
  assert_true(@records.discard_completed(source))
}
