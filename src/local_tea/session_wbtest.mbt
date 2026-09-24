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
