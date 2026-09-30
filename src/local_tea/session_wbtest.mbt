///|
fn session_owner(
  producer : @lower.BoundPrepared,
  by : String,
) -> @lower.BoundPrepared {
  event_window_bind(
    @pipeline.check_with_evidence(
      event_window_cursor("[{\"session\":{\"by\":" + by + ",\"gap\":10}}]"),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(event_window_cursor("\"prior\"")),
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
fn finish_session(execution : SessionExecution) -> @records.Completed {
  while true {
    match advance_session(execution, 1).unwrap() {
      SessionContinue(..) => ()
      SessionComplete(output, ..) => return output
      SessionFailed(issue, ..) =>
        match issue {
          InvalidSessionKernel => abort("invalid session kernel")
          InvalidSessionLimits => abort("invalid session limits")
          SessionInputUnavailable => abort("session input unavailable")
          EmptySessionInput => abort("empty session input")
          InvalidSessionRecord(_) => abort("invalid session record")
          InvalidSessionValue(_, _) => abort("invalid session value")
          DuplicateSessionIdentity(_) => abort("duplicate session identity")
          SessionArithmetic(_) => abort("session arithmetic")
          SessionIdentityLimit => abort("session identity limit")
          SessionControlWorkLimit => abort("session control work limit")
          SessionWorkspaceLimit => abort("session workspace limit")
          SessionOutput(@records.Storage(@storage.ValueLimit)) =>
            abort("session output value limit")
          SessionOutput(@records.Storage(@storage.WorkspaceLimit)) =>
            abort("session output workspace limit")
          SessionOutput(@records.Storage(@storage.WorkLimit)) =>
            abort("session output work limit")
          SessionOutput(@records.Storage(@storage.RetainedValueLimit)) =>
            abort("session output retained value limit")
          SessionOutput(@records.Storage(@storage.RecordLimit)) =>
            abort("session output record limit")
          SessionOutput(@records.Storage(@storage.FieldLimit)) =>
            abort("session output field limit")
          SessionOutput(@records.Storage(@storage.DuplicateIdentity)) =>
            abort("session output duplicate identity")
          SessionOutput(_) => abort("other session output")
          SessionExecutionIssue(_) => abort("session execution")
        }
      SessionStopped(_, ..) => abort("session stopped")
    }
  } nobreak {
    abort("unreachable")
  }
}

///|
fn session_text_field(
  storage : @storage.Storage,
  record : Int,
  name : String,
) -> String {
  let width = @storage.record_field_count(storage, record).unwrap()
  for field in 0..<width {
    let (field_name, value) = @storage.record_field_at(storage, record, field).unwrap()
    if @schema.reference_name(field_name) == name {
      guard value.value is @value.Text(text) else { abort("text field") }
      return text
    }
  }
  abort("missing field " + name)
}

///|
fn session_execution(
  producer : @lower.BoundPrepared,
  owner : @lower.BoundPrepared,
  value_limit : Int,
  control : @bounded.Control,
) -> (SessionExecution, @records.Completed) {
  let source_output = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    event_window_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  @records.append_record(source_output, [
    (@schema.Unqualified("event_id"), event_window_number(1.0)),
    (@schema.Unqualified("occurred_at"), event_window_number(0.0)),
    (@schema.Unqualified("payload"), event_window_text("é")),
  ]).unwrap()
  let source = @records.finish_output(source_output).unwrap()
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_session(
    control,
    event_window_sequence(owner),
    0,
    input,
    {
      ..event_window_limits(),
      max_fields_per_record: 6,
      max_value_bytes: value_limit,
    },
    4096L,
    fn() { true },
  ).unwrap()
  (execution, source)
}

///|
test "session identity generation is bounded by value bytes and quantum" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\"]")
  let (baseline, baseline_source) = session_execution(
    producer,
    owner,
    1000,
    @bounded.control(),
  )
  assert_eq(session_max_noninterruptible_value_bytes(baseline), 1000)
  let baseline_output = finish_session(baseline)
  let baseline_storage = @records.completed_storage(baseline_output).unwrap()
  let identity = session_text_field(baseline_storage, 0, "session_id")
  let identity_bytes = @utf8.encode(identity).length()
  let record_bytes = @storage.measured_input_value_bytes(baseline_storage)
  assert_true(@records.discard_completed(baseline_output))
  assert_true(cleanup_session(baseline).unwrap())
  assert_true(@records.discard_completed(baseline_source))

  let (accepted, accepted_source) = session_execution(
    producer,
    owner,
    record_bytes,
    @bounded.control(),
  )
  let accepted_output = finish_session(accepted)
  assert_eq(
    session_text_field(
      @records.completed_storage(accepted_output).unwrap(),
      0,
      "session_id",
    ),
    identity,
  )
  assert_true(@records.discard_completed(accepted_output))
  assert_true(cleanup_session(accepted).unwrap())
  assert_true(@records.discard_completed(accepted_source))

  let (rejected, rejected_source) = session_execution(
    producer,
    owner,
    identity_bytes - 1,
    @bounded.control(),
  )
  let mut failed = false
  while !failed {
    match advance_session(rejected, 1).unwrap() {
      SessionContinue(..) => ()
      SessionFailed(SessionIdentityLimit, ..) => failed = true
      _ => fail("expected identity limit")
    }
  }
  assert_true(cleanup_session(rejected).unwrap())
  assert_true(@records.discard_completed(rejected_source))
}

///|
test "session identity construction can stop between scalar parts" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\",\"payload\"]")
  let control = @bounded.control()
  let (execution, source) = session_execution(producer, owner, 1000, control)
  for _ in 0..<26 {
    match advance_session(execution, 1).unwrap() {
      SessionContinue(..) => ()
      _ => fail("expected resumable identity construction")
    }
  }
  assert_true(@bounded.request_cancel(control))
  match advance_session(execution, 1).unwrap() {
    SessionStopped(_, ..) => ()
    _ => fail("expected stopped session")
  }
  assert_true(cleanup_session(execution).unwrap())
  assert_true(@records.discard_completed(source))
}

///|
test "session scratch initialization advances within the resume quantum" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\"]")
  let live = Ref(true)
  let source = event_window_source(
    producer,
    [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
    live,
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_session(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      input,
      { ..event_window_limits(), max_workspace_slots: 51, },
      4096L,
      fn() { live.val },
    )
    is Err(SessionWorkspaceLimit),
  )
  let control = @bounded.control()
  let execution = start_session(
    control,
    event_window_sequence(owner),
    0,
    input,
    { ..event_window_limits(), max_workspace_slots: 52, },
    4096L,
    fn() { live.val },
  ).unwrap()
  assert_eq(session_initialization_progress(execution), (0, 0))
  for step in 1..<25 {
    assert_true(
      advance_session(execution, 1).unwrap() is SessionContinue(progress=0L, ..),
    )
    assert_eq(session_initialization_progress(execution), (step, 0))
  }
  assert_true(advance_session(execution, 1).unwrap() is SessionContinue(_))
  assert_eq(session_initialization_progress(execution), (24, 0))
  for step in 1..<9 {
    assert_true(
      advance_session(execution, 1).unwrap() is SessionContinue(progress=0L, ..),
    )
    assert_eq(session_initialization_progress(execution), (24, step))
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_session(execution, 1).unwrap()
    is SessionStopped(@bounded.Cancelled, progress=0L, work=33L),
  )
  assert_true(cleanup_session(execution).unwrap())
  assert_true(@records.producer_read_available(input))

  let stopped_control = @bounded.control()
  assert_true(@bounded.request_cancel(stopped_control))
  let stopped_input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let stopped = start_session(
    stopped_control,
    event_window_sequence(owner),
    0,
    stopped_input,
    { ..event_window_limits(), max_workspace_slots: 52, },
    4096L,
    fn() { live.val },
  ).unwrap()
  assert_eq(session_initialization_progress(stopped), (0, 0))
  assert_true(
    advance_session(stopped, 1).unwrap()
    is SessionStopped(@bounded.Cancelled, progress=0L, work=0L),
  )
  assert_eq(session_initialization_progress(stopped), (0, 0))
  assert_true(cleanup_session(stopped).unwrap())
  assert_true(@records.discard_completed(source))
}

///|
test "session output workspace includes scratch and temporary fields" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\"]")
  let live = Ref(true)
  let source = event_window_source(producer, [0.0], live)
  assert_eq(
    @storage.record_field_count(@records.completed_storage(source).unwrap(), 0).unwrap(),
    3,
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // One record and one key retain 3 cells, 3 indices, and 4 metadata
  // slots. Emitting its 3 source fields plus 3 session fields needs 12
  // temporary slots, so the simultaneous boundary is 10 + 12 = 22.
  for (budget, accepted) in [(22, true), (21, false)] {
    let execution = start_session(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      input,
      { ..event_window_limits(fields=6), max_workspace_slots: budget, },
      4096L,
      fn() { live.val },
    ).unwrap()
    let mut terminal = false
    for _ in 0..<64 {
      if terminal {
        break
      }
      match advance_session(execution, 1).unwrap() {
        SessionContinue(..) => ()
        SessionComplete(output, ..) => {
          assert_true(accepted)
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        SessionFailed(SessionWorkspaceLimit, progress~, work~) => {
          assert_false(accepted)
          assert_eq(progress, 0L)
          assert_true(work > 0L)
          assert_true(session_cleanup_pending(execution))
          terminal = true
        }
        _ => fail("unexpected session workspace outcome")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_session(execution).unwrap())
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}

///|
test "session admits exact and one-short cumulative control work" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\"]")
  let live = Ref(true)
  let source = event_window_source(producer, [0.0], live)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // One row and one key take six scratch initialization steps, eighteen
  // field-loading steps, five ordering steps, one group step, five identity
  // steps, and nine output/finalization steps: 44 charged control units.
  for (budget, accepted) in [(44, true), (43, false)] {
    let execution = start_session(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      input,
      event_window_limits(fields=6),
      4096L,
      fn() { live.val },
      control_work_limit=Some(budget),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<45 {
      if terminal {
        break
      }
      match advance_session(execution, 1).unwrap() {
        SessionContinue(work~, ..) => assert_true(work <= budget.to_int64())
        SessionComplete(output, progress~, work~) => {
          assert_true(accepted)
          assert_eq((progress, work), (1L, 44L))
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        SessionFailed(SessionControlWorkLimit, progress~, work~) => {
          assert_false(accepted)
          assert_eq((progress, work), (1L, 43L))
          assert_true(session_cleanup_pending(execution))
          terminal = true
        }
        SessionFailed(issue, ..) => {
          assert_eq(issue, SessionControlWorkLimit)
          fail("unexpected session failure")
        }
        _ => fail("unexpected session control-work outcome")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_session(execution).unwrap())
    assert_true(@records.producer_read_available(input))
  }
  assert_true(
    start_session(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      input,
      event_window_limits(fields=6),
      4096L,
      fn() { live.val },
      control_work_limit=Some(0),
    )
    is Err(SessionControlWorkLimit),
  )
  assert_true(@records.discard_completed(source))
}

///|
test "empty session input completes on the first bounded resume" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\"]")
  let live = Ref(true)
  let source = event_window_source(producer, [], live)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_session(
    @bounded.control(),
    event_window_sequence(owner),
    0,
    input,
    event_window_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  let output = match advance_session(execution, 1).unwrap() {
    SessionComplete(output, progress=0L, work=1L) => output
    _ => fail("empty session did not complete with bounded work")
  }
  assert_eq(
    @storage.record_count(@records.completed_storage(output).unwrap()),
    0,
  )
  assert_true(cleanup_session(execution).unwrap())
  assert_true(@records.discard_completed(output))
  assert_true(@records.producer_read_available(input))
  assert_true(@records.discard_completed(source))
}

///|
test "empty session retains its metadata and finish limits" {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[\"payload\"]")
  let live = Ref(true)
  let source = event_window_source(producer, [], live)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // No row scratch is needed. Three terms plus their metadata marker need
  // four slots; completing the empty generation costs one finish unit.
  for (workspace, work) in [(4, 1), (3, 1), (4, 0)] {
    let started = start_session(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      input,
      { ..event_window_limits(), max_workspace_slots: workspace, },
      4096L,
      fn() { live.val },
      control_work_limit=Some(work),
    )
    if workspace == 3 {
      assert_true(started is Err(SessionWorkspaceLimit))
    } else if work == 0 {
      assert_true(started is Err(SessionControlWorkLimit))
    } else {
      let execution = started.unwrap()
      let output = match advance_session(execution, 1).unwrap() {
        SessionComplete(output, progress=0L, work=1L) => output
        _ => fail("exact empty session limits did not complete")
      }
      assert_true(cleanup_session(execution).unwrap())
      assert_true(@records.completed_available(output))
      assert_true(@records.discard_completed(output))
    }
    assert_true(@records.producer_read_available(input))
  }
  let control = @bounded.control()
  let cancelled = start_session(
    control,
    event_window_sequence(owner),
    0,
    input,
    { ..event_window_limits(), max_workspace_slots: 4, },
    4096L,
    fn() { live.val },
    control_work_limit=Some(1),
  ).unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_session(cancelled, 1).unwrap() is SessionStopped(_, work=0L, ..),
  )
  assert_true(cleanup_session(cancelled).unwrap())
  assert_true(@records.producer_read_available(input))
  assert_true(@records.discard_completed(source))
}
