///|
test "same parent backs original Local child before entry across both one-byte-short dimensions" {
  assert_eq(program_source_local_entry_bytes, 608L)
  assert_eq(program_source_local_entry_retained_bytes, 416L)
  for retention in [true, false] {
    let (parent, owner, input) = registration_pipeline_fixture()
    prepare_program_check_source_pipeline(owner).unwrap() |> ignore
    reconcile_program_check_source_pipeline(owner).unwrap()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    let prefix = @context.source_registration_pipeline_work(read)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 608L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 608L + 1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_local_entry(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(@context.source_registration_local_entry_work(read) is None)
    assert_true(@context.source_registration_local_phase(read) is None)
    assert_eq(@context.source_registration_pipeline_work(read), prefix)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      prepare_program_check_source_local_entry(owner).unwrap(),
      RegistrationLocal,
    )
    let observed = @context.source_registration_local_entry_work(read)
    assert_true(observed is Some(spent) && spent >= 3)
    assert_true(
      @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentIndex),
    )
    assert_true(@context.source_registration_local_index_usage(read) is None)
    assert_true(@context.source_registration_local_groups_work(read) is None)
    assert_eq(@context.source_registration_pipeline_work(read), prefix)
    assert_true(
      prepare_program_check_source_local_entry(owner) is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalEntry,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_local_entry(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 416L, before.1 + 416L)),
    )
    assert_true(
      physical_equal(
        take_program_check_source_registration(owner).unwrap(),
        original,
      ),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    @context.clear_source_registration(read)
    assert_true(
      physical_equal(
        observed,
        @context.source_registration_local_entry_work(read),
      ),
    )
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap()
    |> ignore
    preparation_initial_cleanup(parent.initial).unwrap()
  }
}

///|
test "Local entrance current callback cannot reenter or construct a child after stop" {
  let stop = Ref(false)
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = registration_pipeline_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  prepare_program_check_source_pipeline(owner).unwrap() |> ignore
  reconcile_program_check_source_pipeline(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if prepare_program_check_source_local_entry(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  stop.val = true
  let before = calls.val
  assert_true(
    prepare_program_check_source_local_entry(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  assert_true(@context.source_registration_local_entry_work(read) is None)
  assert_true(@context.source_registration_local_phase(read) is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
