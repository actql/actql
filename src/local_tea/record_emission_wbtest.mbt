///|
priv enum EmissionFixture {
  Watermark(WatermarkExecution)
  Window(EventWindowExecution)
  Dedupe(DedupeExecution)
  Session(SessionExecution)
}

///|
priv enum EmissionOutcome {
  Continue(Int64)
  Complete(@records.Completed, Int64)
  WorkLimit(Int64)
  WorkspaceLimit
  Stopped(Int64)
}

///|
fn emission_start(
  kind : Int,
  producer : @lower.BoundPrepared,
  source : @records.Completed,
  control : @bounded.Control,
  slots : Int,
  work : Int,
) -> (EmissionFixture, @records.ProducerRead) {
  let owner = match kind {
    0 => watermark_owner(producer, "mark")
    1 => event_window_owner(producer, "{\"kind\":\"fixed\",\"size\":10}")
    2 =>
      dedupe_owner(
        producer, "[\"event_id\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
      )
    _ => session_owner(producer, "[\"event_id\"]")
  }
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let limits = { ..limits(workspace=slots), max_value_bytes: 2000, }
  let sequence = sequence(owner)
  let fixture = match kind {
    0 =>
      Watermark(
        start_watermark(
          control,
          sequence,
          0,
          input,
          limits,
          4096L,
          fn() { true },
          control_work_limit=Some(work),
        ).unwrap(),
      )
    1 =>
      Window(
        start_event_window(
          control,
          sequence,
          0,
          input,
          limits,
          4096L,
          fn() { true },
          control_work_limit=Some(work),
        ).unwrap(),
      )
    2 =>
      Dedupe(
        start_dedupe(
          control,
          sequence,
          0,
          input,
          limits,
          4096L,
          fn() { true },
          control_work_limit=Some(work),
        ).unwrap(),
      )
    _ =>
      Session(
        start_session(
          control,
          sequence,
          0,
          input,
          limits,
          4096L,
          fn() { true },
          control_work_limit=Some(work),
        ).unwrap(),
      )
  }
  (fixture, input)
}

///|
fn emission_advance(
  fixture : EmissionFixture,
  quantum : Int,
) -> EmissionOutcome {
  match fixture {
    Watermark(value) =>
      match advance_watermark(value, quantum).unwrap() {
        Continue(work~, ..) => Continue(work)
        Complete(output, work~, ..) => Complete(output, work)
        Failed(ControlWorkLimit, work~, ..) => WorkLimit(work)
        Failed(WorkspaceLimit, ..) => WorkspaceLimit
        Stopped(_, work~, ..) => Stopped(work)
        _ => abort("unexpected watermark emission outcome")
      }
    Window(value) =>
      match advance_event_window(value, quantum).unwrap() {
        EventWindowContinue(work~, ..) => Continue(work)
        EventWindowComplete(output, work~, ..) => Complete(output, work)
        EventWindowFailed(EventWindowWorkLimit, work~, ..) => WorkLimit(work)
        EventWindowFailed(EventWindowWorkspaceLimit, ..) => WorkspaceLimit
        EventWindowStopped(_, work~, ..) => Stopped(work)
        _ => abort("unexpected window emission outcome")
      }
    Dedupe(value) =>
      match advance_dedupe(value, quantum).unwrap() {
        DedupeContinue(work~, ..) => Continue(work)
        DedupeComplete(output, work~, ..) => Complete(output, work)
        DedupeFailed(DedupeControlWorkLimit, work~, ..) => WorkLimit(work)
        DedupeFailed(DedupeWorkspaceLimit, ..) => WorkspaceLimit
        DedupeStopped(_, work~, ..) => Stopped(work)
        _ => abort("unexpected dedupe emission outcome")
      }
    Session(value) =>
      match advance_session(value, quantum).unwrap() {
        SessionContinue(work~, ..) => Continue(work)
        SessionComplete(output, work~, ..) => Complete(output, work)
        SessionFailed(SessionControlWorkLimit, work~, ..) => WorkLimit(work)
        SessionFailed(SessionWorkspaceLimit, ..) => WorkspaceLimit
        SessionStopped(_, work~, ..) => Stopped(work)
        _ => abort("unexpected session emission outcome")
      }
  }
}

///|
fn emission_cleanup(fixture : EmissionFixture) -> Bool {
  match fixture {
    Watermark(value) => cleanup_watermark(value).unwrap()
    Window(value) => cleanup_event_window(value).unwrap()
    Dedupe(value) => cleanup_dedupe(value).unwrap()
    Session(value) => cleanup_session(value).unwrap()
  }
}

///|
fn emission_append_active(fixture : EmissionFixture) -> Bool {
  match fixture {
    Watermark(value) => value.state.append is Some(_)
    Window(value) => value.state.append is Some(_)
    Dedupe(value) => value.state.append is Some(_)
    Session(value) => value.state.append is Some(_)
  }
}

///|
fn emission_output(fixture : EmissionFixture) -> @records.OutputBuilder? {
  match fixture {
    Watermark(value) => value.state.output
    Window(value) => value.state.output
    Dedupe(value) => value.state.output
    Session(value) => value.state.output
  }
}

///|
fn emission_source(producer : @lower.BoundPrepared) -> @records.Completed {
  let output = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let payload = @value.checked_text_value(
    String::make(513, 'a'),
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
  @records.append_record(output, [
    (@schema.Unqualified("event_id"), number(1.0)),
    (@schema.Unqualified("occurred_at"), number(0.0)),
    (@schema.Unqualified("payload"), payload),
  ]).unwrap()
  @records.finish_output(output).unwrap()
}

///|
test "Events record emission keeps independent control and workspace limits" {
  // A primitive Events append takes 6*width + 2*identities + 8 polls.
  // Text length 513 adds Read + ceil(513/64) - 1 = nine extra polls.
  // Watermark: 7 outer + 46 + 9 = 62. Fixed window: 13 + 40 + 9 = 62.
  // Dedupe: 31 + 28 + 9 = 68. Session: 44 + 46 + 9 = 99.
  // Cursor 16+3*width+identities+3*depth, caller scratch, next row coexist.
  // Peaks: 65+7+8=80; 62+10+7=79; 56+9+5=70; 65+17+8=90.
  for
    (kind, work, slots, logical) in [
      (0, 62, 80, 28),
      (1, 62, 79, 24),
      (2, 68, 70, 16),
      (3, 99, 90, 28),
    ] {
    let producer = producer_owner(false)
    let source = emission_source(producer)
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
        )
        let mut terminal = false
        let mut prior = 0L
        for _ in 0..<150 {
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
              let evidence = @records.completed_evidence(output).unwrap()
              assert_eq(@records.evidence_construction_work(evidence), logical)
              assert_eq(
                session_text_field(storage, 0, "payload"),
                String::make(513, 'a'),
              )
              assert_eq(event_window_field(storage, 0, "event_id"), 1.0)
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
            _ => fail("unexpected Events emission terminal")
          }
        }
        assert_true(terminal)
        assert_true(emission_cleanup(fixture))
        assert_false(emission_cleanup(fixture))
        assert_true(emission_output(fixture) is None)
        assert_true(@records.producer_read_available(input))
      }
    }
    assert_true(@records.discard_completed(source))
  }
}

///|
test "Events record emission yields inside unused Text and keeps stop custody" {
  for kind in 0..<4 {
    let producer = producer_owner(false)
    let source = emission_source(producer)
    let control = @bounded.control()
    let (fixture, input) = emission_start(
      kind, producer, source, control, 1000, 1000,
    )
    let mut charged = 0L
    for _ in 0..<100 {
      if emission_append_active(fixture) {
        break
      }
      match emission_advance(fixture, 1) {
        Continue(work) => charged = work
        _ => fail("emission must yield before append")
      }
    }
    assert_true(emission_append_active(fixture))
    // Enter the long payload's wire continuation, not just append startup.
    for _ in 0..<32 {
      match emission_advance(fixture, 1) {
        Continue(work) => charged = work
        _ => fail("emission must yield inside Text")
      }
    }
    assert_true(emission_append_active(fixture))
    let output = emission_output(fixture).unwrap()
    let custody = @records.output_workspace_slots(output)
    assert_true(custody > 0)
    assert_true(@bounded.request_cancel(control))
    assert_eq(@records.output_workspace_slots(output), custody)
    assert_true(emission_append_active(fixture))
    assert_true(@records.producer_read_available(input))
    match emission_advance(fixture, 1) {
      Stopped(work) => assert_eq(work, charged)
      _ => fail("cancelled emission must stop without additional work")
    }
    assert_eq(@records.output_workspace_slots(output), custody)
    assert_true(emission_cleanup(fixture))
    assert_false(emission_cleanup(fixture))
    assert_false(emission_append_active(fixture))
    assert_eq(@records.output_workspace_slots(output), 0)
    assert_true(@records.producer_read_available(input))
    assert_true(@records.discard_completed(source))
  }
}
