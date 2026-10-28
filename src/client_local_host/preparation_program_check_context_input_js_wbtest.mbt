///|
fn context_entry_parent(
  count : Int,
  current? : () -> Bool = () => true,
  calendar_policy? : String = "{}",
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let (parent, owner, input) = batch_snapshot_parent(
    count,
    local_declarations=true,
    current~,
    calendar_policy~,
  )
  prepare_program_check_source_local_snapshots(owner).unwrap() |> ignore
  prepare_program_check_source_local_tail(owner).unwrap() |> ignore
  reconcile_program_check_source_local_tail(owner).unwrap()
  (parent, owner, input)
}

///|
test "same Request parent backs original Context registration entrance without running its topology or binding" {
  for count in [0, 2] {
    let (parent, owner, input) = context_entry_parent(count)
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    prepare_program_check_source_context_input(owner).unwrap()
    assert_true(owner.phase == SourceContextInputPrepared)
    assert_true(owner.work is None)
    assert_eq(@context.source_registration_phase(read), RegistrationTransferred)
    let context = @checked.parsed_source_context_input(original)
      .unwrap()
      .unwrap()
    assert_true(
      physical_equal(
        @context.sourceview_context_input_source(context),
        owner.arguments.unwrap().source_preparation.unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        @checked.prepare_parsed_source_context_input(original).unwrap(),
        context,
      ),
    )
    assert_true(@context.sourceview_context_input_work(context) > 0)
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceContextInputBody,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_context_input(owner).unwrap()
    assert_true(owner.phase == SourceContextInputComplete)
    assert_true(
      prepare_program_check_source_context_input(owner) is Err(WrongPhase),
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "Context entry one-short grow retains original geometry and does not consume registration before admission" {
  for retention in [true, false] {
    let (parent, owner, input) = context_entry_parent(2)
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    inspect_program_check_context_input(owner).unwrap()
    let geometry = @checked.parsed_source_context_input_geometry(original).unwrap()
    quote_program_check_context_input(owner, original).unwrap()
    let quote = owner.source_body_quote.unwrap()
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        quote.0 +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - quote.0 + 1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_context_input(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == SourceContextInputRetained)
    assert_true(owner.work is None)
    assert_true(physical_equal(owner.source_body_quote.unwrap(), quote))
    assert_true(
      physical_equal(
        @checked.parsed_source_context_input_geometry(original).unwrap(),
        geometry,
      ),
    )
    assert_true(@checked.parsed_source_context_input(original) is None)
    assert_eq(@context.source_registration_phase(read), RegistrationComplete)
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceContextInputInspection,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    prepare_program_check_source_context_input(owner).unwrap()
    assert_true(@checked.parsed_source_context_input(original) is Some(Ok(_)))
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "original Context header Calendar refusal retains exact failed result and missing work until cleanup" {
  let (parent, owner, input) = context_entry_parent(
    1,
    calendar_policy="{\"calendar\":{}}",
  )
  let original = owner.source_registration.unwrap()
  assert_true(
    prepare_program_check_source_context_input(owner)
    is Err(
      SourceRegistration(
        ContextInput(Program(CalendarSelection(InvalidComponent)))
      )
    ),
  )
  assert_true(owner.phase == SourceContextInputFailed)
  let failed = @checked.parsed_source_context_input(original)
  assert_true(failed is Some(Err(Program(CalendarSelection(InvalidComponent)))))
  assert_true(
    physical_equal(@checked.parsed_source_context_input(original), failed),
  )
  let work = owner.work.unwrap()
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.SemanticCheck,
      1L,
    )
    is Err(WrongPhase),
  )
  assert_true(take_program_check_source_registration(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@resources.finish_preparation_phase_work64(work), Err(Closed))
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "Context entrance current refuses reentry and stop before geometry or registration is captured" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let stop = Ref(false)
  let (parent, owner, _) = context_entry_parent(0, current=() => {
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  let original = owner.source_registration.unwrap()
  let flags = Ref(0)
  action.val = Some(() => {
    if prepare_program_check_source_context_input(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  stop.val = true
  assert_true(
    prepare_program_check_source_context_input(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(flags.val, 7)
  assert_true(@checked.parsed_source_context_input_geometry(original) is None)
  assert_true(@checked.parsed_source_context_input(original) is None)
  assert_true(owner.work is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "original Context entrance cannot resume after its owning parent continuation is cleared" {
  let (parent, owner, _) = context_entry_parent(0)
  let original = owner.source_registration.unwrap()
  prepare_program_check_source_context_input(owner).unwrap()
  let input = @checked.parsed_source_context_input(original).unwrap().unwrap()
  clear_program_check_preparation(owner).unwrap()
  // These are semantic retirement checks before any later constructor. The
  // original parent has not yet been settled, and no topology is run on red.
  assert_true(
    @checked.prepare_parsed_source_context_input(original) is Err(Unavailable),
  )
  assert_true(
    @checked.finish_parsed_source_registration(original) is Err(Unavailable),
  )
  assert_true(
    @context.prepare_sourceview_context_from_input(input, None, [])
    is Err(Program(Unavailable)),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
}
