///|
fn registration_local_index_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let (parent, owner, input) = registration_pipeline_fixture(current~)
  prepare_program_check_source_pipeline(owner).unwrap() |> ignore
  prepare_program_check_source_local_entry(owner).unwrap() |> ignore
  reconcile_program_check_source_local_entry(owner).unwrap()
  (parent, owner, input)
}

///|
test "same parent funds original Local Index metadata and body across both one-short boundaries" {
  assert_eq(program_source_local_index_quote_bytes, 4136L)
  assert_eq(program_source_local_index_metadata_peak_bytes, 4696L)
  assert_eq(program_source_local_index_metadata_retained_bytes, 4352L)
  for retention in [true, false] {
    let (parent, owner, input) = registration_local_index_fixture()
    let read = @checked.parsed_source_registration_read(
      owner.source_registration.unwrap(),
    )
    let initial = @context.source_registration_local_entry_work(read)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 4696L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 4696L + 1L
      },
    ).unwrap()
    let refused = inspect_program_check_source_local_index(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      @context.source_registration_local_index_inspection_work(read) is None,
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    inspect_program_check_source_local_index(owner).unwrap()
    let observed = @context.source_registration_local_index_inspection_work(
      read,
    )
    assert_true(observed is Some(_))
    reconcile_program_check_source_local_index_inspection(owner).unwrap()
    let metadata = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(metadata, (before.0 + 4352L, before.1 + 4352L))
    let full = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - metadata.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - metadata.1
      },
    ).unwrap()
    assert_true(
      prepare_program_check_source_local_index(owner) is Err(Capacity(_)),
    )
    let quote = owner.source_body_quote.unwrap()
    @resources.settle_capacity(parent.ledger, full).unwrap()
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - metadata.0 - quote.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - metadata.1 - quote.0 + 1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_local_index(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(physical_equal(quote, owner.source_body_quote.unwrap()))
    assert_true(
      physical_equal(
        observed,
        @context.source_registration_local_index_inspection_work(read),
      ),
    )
    assert_true(@context.source_registration_local_index_usage(read) is None)
    @resources.settle_capacity(parent.ledger, short).unwrap()
    assert_eq(
      prepare_program_check_source_local_index(owner).unwrap(),
      RegistrationLocal,
    )
    assert_true(
      @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentGroups),
    )
    let used = @context.source_registration_local_index_usage(read)
    assert_true(used is Some(usage) && usage.work > 0)
    assert_true(
      physical_equal(
        initial,
        @context.source_registration_local_entry_work(read),
      ),
    )
    assert_true(
      prepare_program_check_source_local_index(owner) is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalIndex,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_local_index(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 216L + quote.1, before.1 + 216L + quote.1)),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_eq(@context.source_registration_local_index_usage(read), used)
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "Local Index body observes current once and retains metadata when stopped or reentered" {
  let stop = Ref(false)
  let calls = Ref(0)
  let reentry = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = registration_local_index_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  inspect_program_check_source_local_index(owner).unwrap()
  reconcile_program_check_source_local_index_inspection(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let metadata = @context.source_registration_local_index_inspection_work(read)
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      reentry.val += 1
    }
    if prepare_program_check_source_local_index(owner) is Err(WrongPhase) {
      reentry.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      reentry.val += 4
    }
  })
  stop.val = true
  let before = calls.val
  assert_true(
    prepare_program_check_source_local_index(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(reentry.val, 7)
  assert_true(
    @context.source_registration_local_phase(read)
    is Some(LocalEnvironmentIndex),
  )
  assert_true(@context.source_registration_local_index_usage(read) is None)
  assert_true(
    physical_equal(
      metadata,
      @context.source_registration_local_index_inspection_work(read),
    ),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
