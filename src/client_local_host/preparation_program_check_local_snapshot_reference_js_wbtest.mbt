///|
test "same parent funds first original Member Reference observation before either one-short limit" {
  assert_eq(program_source_snapshot_reference_peak_bytes, 2352L)
  assert_eq(program_source_snapshot_reference_retained_bytes, 184L)
  for retention in [true, false] {
    let (parent, owner, input) = registration_local_snapshot_fixture()
    inspect_program_check_source_local_snapshot(owner).unwrap()
    reconcile_program_check_source_local_snapshot_inspection(owner).unwrap()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let cap = @resources.ledger_limits(parent.ledger)
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        cap.retained_bytes - before.0 - 2352L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        cap.execution_bytes - before.1 - 2352L + 1L
      },
    ).unwrap()
    let refused = inspect_program_check_source_local_snapshot_reference(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      @context.source_registration_local_snapshot_reference_construction(read)
      is None,
    )
    assert_true(owner.work is None)
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(before),
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    inspect_program_check_source_local_snapshot_reference(owner).unwrap()
    let observed = @context.source_registration_local_snapshot_reference_construction(
      read,
    ).unwrap()
    assert_true(observed.0 is Some(_))
    assert_eq(observed.1, 9L)
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 2352L, before.1 + 2352L)),
    )
    assert_true(
      inspect_program_check_source_local_snapshot_reference(owner)
      is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalSnapshotReferenceInspection,
        12L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_local_snapshot_reference(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 184L, before.1 + 184L)),
    )
    assert_true(
      physical_equal(
        observed,
        @context.source_registration_local_snapshot_reference_construction(read).unwrap(),
      ),
    )
    assert_true(
      @context.source_registration_local_snapshot_emission(read) is None,
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
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap()
    |> ignore
    preparation_initial_cleanup(parent.initial).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "Reference observation checks original current once and blocks reentry before field or recipe work" {
  let stop = Ref(false)
  let calls = Ref(0)
  let reentry = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, input) = registration_local_snapshot_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  inspect_program_check_source_local_snapshot(owner).unwrap()
  reconcile_program_check_source_local_snapshot_inspection(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      reentry.val += 1
    }
    if inspect_program_check_source_local_snapshot_reference(owner)
      is Err(WrongPhase) {
      reentry.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      reentry.val += 4
    }
  })
  stop.val = true
  let previous = calls.val
  assert_true(
    inspect_program_check_source_local_snapshot_reference(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val - previous, 1)
  assert_eq(reentry.val, 7)
  assert_true(
    @context.source_registration_local_snapshot_reference_construction(read)
    is None,
  )
  assert_true(owner.work is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok(before),
  )
  assert_true(
    @context.source_registration_local_snapshot_emission(read) is None,
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "claimed Reference work is not reset or observed on the original parent's failure path" {
  let (parent, owner, input) = registration_local_snapshot_fixture()
  inspect_program_check_source_local_snapshot(owner).unwrap()
  reconcile_program_check_source_local_snapshot_inspection(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let original = @resources.begin_preparation_phase_work64(
    parent.capacity,
    input,
    @resources.SourceLocalSnapshotReferenceInspection,
    12L,
  ).unwrap()
  @resources.spend_preparation_phase_work64(original, 3L).unwrap()
  assert_eq(@resources.finish_preparation_phase_work64(original), Ok(3L))
  assert_true(
    inspect_program_check_source_local_snapshot_reference(owner)
    is Err(Work(AlreadyClaimed)),
  )
  assert_true(
    @context.source_registration_local_snapshot_reference_construction(read)
    is None,
  )
  assert_true(
    inspect_program_check_source_local_snapshot_reference(owner)
    is Err(WrongPhase),
  )
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.SourceLocalSnapshotReferenceInspection,
      12L,
    )
    is Err(AlreadyClaimed),
  )
  assert_true(
    @context.source_registration_local_snapshot_emission(read) is None,
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
