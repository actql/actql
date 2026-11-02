///|
test "same Request parent funds collection metadata and body once across independent one-short boundaries" {
  // Independent original two-Stage fixture: retained Inputs/empty Map672,
  // frame3048 + Stage1512 + Local-input744 + issue432, read controls248.
  assert_eq(program_source_collection_quote_bytes, 22120L)
  assert_eq(program_source_collection_metadata_peak_bytes, 24784L)
  assert_eq(program_source_collection_metadata_retained_bytes, 22400L)
  for retention in [true, false] {
    let (parent, owner, source, input) = registration_parent_fixture()
    prepare_program_check_source_registration(owner, source).unwrap()
    reconcile_program_check_source_registration(owner).unwrap()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 24784L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 24784L + 1L
      },
    ).unwrap()
    let rejected = inspect_program_check_source_collection(owner)
    assert_true(
      if retention {
        rejected is Err(Capacity(Resource(RetentionLimit)))
      } else {
        rejected is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == SourceRegistrationRetained)
    assert_true(
      @context.source_registration_collection_inspection_work(read) is None,
    )
    assert_true(owner.work is None)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    inspect_program_check_source_collection(owner).unwrap()
    let observed = @context.source_registration_collection_inspection_work(read)
    assert_true(observed is Some(n) && n > 0L)
    assert_eq(@context.source_registration_collection_work(read), 0)
    assert_eq(@context.source_registration_phase(read), RegistrationCollect)
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 24784L, before.1 + 24784L)),
    )
    reconcile_program_check_source_collection_inspection(owner).unwrap()
    let metadata = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(metadata, (before.0 + 22400L, before.1 + 22400L))
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - metadata.0 - 6656L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - metadata.1 - 6656L + 1L
      },
    ).unwrap()
    let rejected = prepare_program_check_source_collection(owner)
    assert_true(
      if retention {
        rejected is Err(Capacity(Resource(RetentionLimit)))
      } else {
        rejected is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    let quote = owner.source_body_quote.unwrap()
    assert_eq(quote, (6656L, 704L))
    assert_true(owner.phase == SourceCollectionMetadataRetained)
    assert_true(
      physical_equal(
        observed,
        @context.source_registration_collection_inspection_work(read),
      ),
    )
    assert_eq(@context.source_registration_collection_work(read), 0)
    assert_true(
      inspect_program_check_source_collection(owner) is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceCollectionInspection,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      prepare_program_check_source_collection(owner).unwrap(),
      RegistrationSelect,
    )
    assert_true(physical_equal(quote, owner.source_body_quote.unwrap()))
    assert_true(
      physical_equal(
        observed,
        @context.source_registration_collection_inspection_work(read),
      ),
    )
    let inputs = @context.source_registration_collected_inputs(read).unwrap()
    assert_true(@context.source_registration_collection_work(read) > 0)
    assert_true(owner.work is None)
    assert_true(
      prepare_program_check_source_collection(owner) is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceCollection,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_collection(owner).unwrap()
    let held = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(held, (before.0 + 984L, before.1 + 984L))
    assert_true(
      physical_equal(
        inputs,
        @context.source_registration_collected_inputs(read).unwrap(),
      ),
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
    assert_eq(@context.source_registration_phase(read), RegistrationSelect)
    @context.clear_source_registration(read)
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap()
    |> ignore
    preparation_initial_cleanup(parent.initial).unwrap()
  }
}

///|
test "collection original current gates refuse stop and synchronous reentry without repeating metadata" {
  let stop = Ref(false)
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, source, _) = registration_parent_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  prepare_program_check_source_registration(owner, source).unwrap()
  reconcile_program_check_source_registration(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if inspect_program_check_source_collection(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let before = calls.val
  inspect_program_check_source_collection(owner).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  let observed = @context.source_registration_collection_inspection_work(read)
  reconcile_program_check_source_collection_inspection(owner).unwrap()
  stop.val = true
  let before = calls.val
  assert_true(
    prepare_program_check_source_collection(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_eq(calls.val - before, 1)
  assert_eq(@context.source_registration_collection_work(read), 0)
  assert_true(
    physical_equal(
      observed,
      @context.source_registration_collection_inspection_work(read),
    ),
  )
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@context.source_registration_phase(read), RegistrationRetired)
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "same-parent collection retains typed remote refusal and full failure backing through cleanup" {
  let text = request_check_wire.replace(
    old="\"inputs\":{}",
    new="\"inputs\":{\"remote\":{\"connector\":\"\",\"resource\":\"records\"}}",
  )
  let (parent, owner, source, input) = registration_parent_fixture(text~)
  prepare_program_check_source_registration(owner, source).unwrap()
  inspect_program_check_source_collection(owner).unwrap()
  reconcile_program_check_source_collection_inspection(owner).unwrap()
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  assert_eq(
    prepare_program_check_source_collection(owner).unwrap(),
    RegistrationFailed,
  )
  assert_true(owner.phase == SourceCollectionFailed && owner.work is None)
  let quote = owner.source_body_quote.unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let spent = @context.source_registration_collection_work(read)
  assert_true(spent > 0)
  assert_true(
    reconcile_program_check_source_collection(owner) is Err(WrongPhase),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok((before.0 + quote.0, before.1 + quote.0)),
  )
  assert_true(prepare_program_check_source_collection(owner) is Err(WrongPhase))
  assert_eq(@context.source_registration_collection_work(read), spent)
  // Original semantic issue remains in the original read, not a capacity tag.
  assert_true(
    @context.take_source_registration_result(read) is Some(Err(Declarations(_))),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
