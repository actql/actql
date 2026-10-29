///|
test "same Request parent completes Local declarations reconciliation and assembly with one original work phase" {
  for count in [0, 1, 2, 12] {
    let (parent, owner, input) = batch_snapshot_parent(
      count,
      local_declarations=true,
    )
    prepare_program_check_source_local_snapshots(owner).unwrap() |> ignore
    let read = @checked.parsed_source_registration_read(
      owner.source_registration.unwrap(),
    )
    assert_eq(
      prepare_program_check_source_local_tail(owner).unwrap(),
      RegistrationComplete,
    )
    assert_true(owner.phase == SourceLocalTailPrepared)
    assert_true(owner.work is None)
    assert_true(
      @context.source_registration_local_tail_work(read) is Some(n) && n >= 0,
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalTailBody,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_local_tail(owner).unwrap()
    assert_true(owner.phase == SourceLocalTailComplete)
    assert_true(
      prepare_program_check_source_local_tail(owner) is Err(WrongPhase),
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
test "Local body one-short grow retains completed metadata and the same quote without a second inspection" {
  for retention in [true, false] {
    let (parent, owner, input) = batch_snapshot_parent(
      2,
      local_declarations=true,
    )
    prepare_program_check_source_local_snapshots(owner).unwrap() |> ignore
    inspect_program_check_local_tail_metadata(owner).unwrap()
    let read = @checked.parsed_source_registration_read(
      owner.source_registration.unwrap(),
    )
    let metadata = @context.source_registration_local_tail_construction(read).unwrap()
    quote_program_check_local_tail_body(owner, read).unwrap()
    let original = owner.source_body_quote.unwrap()
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        original.0 +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes -
        usage.reserved_execution_bytes -
        original.0 +
        1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_local_tail(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == SourceLocalTailRetained)
    assert_true(owner.work is None)
    assert_true(physical_equal(owner.source_body_quote.unwrap(), original))
    assert_true(
      physical_equal(
        @context.source_registration_local_tail_construction(read).unwrap(),
        metadata,
      ),
    )
    assert_true(@context.source_registration_local_tail_work(read) is None)
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalTailInspection,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      prepare_program_check_source_local_tail(owner).unwrap(),
      RegistrationComplete,
    )
    assert_true(
      @context.source_registration_local_tail_construction(read) is None,
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "later Local reconciliation failure keeps missing Usage and active receipt until original cleanup" {
  let (parent, owner, input) = batch_snapshot_parent(
    1,
    local_declarations=true,
    bad_tail=true,
  )
  prepare_program_check_source_local_snapshots(owner).unwrap() |> ignore
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  assert_eq(
    prepare_program_check_source_local_tail(owner).unwrap(),
    RegistrationFailed,
  )
  assert_true(owner.phase == SourceLocalTailFailed)
  assert_true(@context.source_registration_local_tail_work(read) is None)
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
  assert_true(prepare_program_check_source_local_tail(owner) is Err(WrongPhase))
  assert_true(take_program_check_source_registration(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@resources.finish_preparation_phase_work64(work), Err(Closed))
  assert_true(@context.source_registration_local_tail_work(read) is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "Local tail current callback cannot reenter or construct metadata after stop" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let stop = Ref(false)
  let (parent, owner, _) = batch_snapshot_parent(1, local_declarations=true, current=() => {
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  prepare_program_check_source_local_snapshots(owner).unwrap() |> ignore
  reconcile_program_check_source_local_snapshots(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let reentry = Ref(0)
  action.val = Some(() => {
    if prepare_program_check_source_local_tail(owner) is Err(WrongPhase) {
      reentry.val += 1
    }
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      reentry.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      reentry.val += 4
    }
  })
  stop.val = true
  assert_true(
    prepare_program_check_source_local_tail(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(reentry.val, 7)
  assert_true(
    @context.source_registration_local_tail_construction(read) is None,
  )
  assert_true(@context.source_registration_local_tail_work(read) is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "original Local scoring tail completes with separate Connector Snapshot evidence on the same parent" {
  let (parent, owner, _) = batch_snapshot_parent(
    2,
    local_declarations=true,
    scores=true,
    mixed=true,
  )
  prepare_program_check_source_local_snapshots(owner).unwrap() |> ignore
  assert_eq(
    prepare_program_check_source_local_tail(owner).unwrap(),
    RegistrationComplete,
  )
  assert_true(owner.phase == SourceLocalTailPrepared)
  assert_true(owner.work is None)
  reconcile_program_check_source_local_tail(owner).unwrap()
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
