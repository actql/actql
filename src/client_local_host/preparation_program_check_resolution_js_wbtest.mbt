///|
test "same parent funds original Source selection once without repeating collection or a failed quote" {
  assert_eq(program_source_resolution_quote_bytes, 4400L)
  assert_eq(program_source_resolution_metadata_peak_bytes, 5112L)
  assert_eq(program_source_resolution_metadata_retained_bytes, 4624L)
  for retention in [true, false] {
    let (parent, owner, source, input) = registration_parent_fixture()
    prepare_program_check_source_registration(owner, source).unwrap()
    inspect_program_check_source_collection(owner).unwrap()
    prepare_program_check_source_collection(owner).unwrap() |> ignore
    reconcile_program_check_source_collection(owner).unwrap()
    let old_quote = owner.source_body_quote.unwrap()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    let inputs = @context.source_registration_collected_inputs(read).unwrap()
    let prefix = @context.source_registration_collection_work(read)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 5112L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 5112L + 1L
      },
    ).unwrap()
    let refused = inspect_program_check_source_resolution(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      owner.phase == SourceResolutionInitial && owner.source_body_quote is None,
    )
    assert_true(
      @context.source_registration_resolution_inspection_work(read) is None,
    )
    assert_eq(@context.source_registration_collection_work(read), prefix)
    assert_true(
      physical_equal(
        inputs,
        @context.source_registration_collected_inputs(read).unwrap(),
      ),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    inspect_program_check_source_resolution(owner).unwrap()
    let observed = @context.source_registration_resolution_inspection_work(read)
    assert_true(observed is Some(_))
    reconcile_program_check_source_resolution_inspection(owner).unwrap()
    let metadata = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(metadata, (before.0 + 4624L, before.1 + 4624L))
    // Deny every positive grow once so the actual original quote is retained.
    // This is fixture occupancy, not a different product limit or budget.
    let all = @resources.reserve_capacity(
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
      prepare_program_check_source_resolution(owner) is Err(Capacity(_)),
    )
    let quote = owner.source_body_quote.unwrap()
    assert_true(!physical_equal(old_quote, quote))
    assert_true(quote.0 > 0L && quote.1 <= quote.0)
    @resources.settle_capacity(parent.ledger, all).unwrap()
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
    let refused = prepare_program_check_source_resolution(owner)
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
        @context.source_registration_resolution_inspection_work(read),
      ),
    )
    assert_eq(@context.source_registration_selection_work(read), 0)
    assert_true(
      inspect_program_check_source_resolution(owner) is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceResolutionInspection,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    @resources.settle_capacity(parent.ledger, short).unwrap()
    assert_eq(
      prepare_program_check_source_resolution(owner).unwrap(),
      RegistrationPipeline,
    )
    assert_eq(@context.source_registration_collection_work(read), prefix)
    assert_true(
      physical_equal(
        inputs,
        @context.source_registration_collected_inputs(read).unwrap(),
      ),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceSelection,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    assert_true(
      prepare_program_check_source_resolution(owner) is Err(WrongPhase),
    )
    reconcile_program_check_source_resolution(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 224L + quote.1, before.1 + 224L + quote.1)),
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
  }
}

///|
test "resolution stop and reentry preserve the same collected inputs and pending selection" {
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
  inspect_program_check_source_collection(owner).unwrap()
  prepare_program_check_source_collection(owner).unwrap() |> ignore
  reconcile_program_check_source_collection(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if inspect_program_check_source_resolution(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let before = calls.val
  inspect_program_check_source_resolution(owner).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  reconcile_program_check_source_resolution_inspection(owner).unwrap()
  let observed = @context.source_registration_resolution_inspection_work(read)
  stop.val = true
  let before = calls.val
  assert_true(
    prepare_program_check_source_resolution(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_eq(calls.val - before, 1)
  assert_eq(@context.source_registration_phase(read), RegistrationSelect)
  assert_eq(@context.source_registration_selection_work(read), 0)
  assert_true(
    physical_equal(
      observed,
      @context.source_registration_resolution_inspection_work(read),
    ),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "original unresolved Source selection retains its own typed issue and full failure peak" {
  let text = request_check_wire.replace(
    old="\"inputs\":{}",
    new="\"inputs\":{\"remote\":{\"connector\":\"crm/not-in-the-fixture\",\"resource\":\"records\"}}",
  )
  let (parent, owner, source, input) = registration_parent_fixture(text~)
  prepare_program_check_source_registration(owner, source).unwrap()
  inspect_program_check_source_collection(owner).unwrap()
  assert_eq(
    prepare_program_check_source_collection(owner).unwrap(),
    RegistrationSelect,
  )
  inspect_program_check_source_resolution(owner).unwrap()
  reconcile_program_check_source_resolution_inspection(owner).unwrap()
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  let prefix = @context.source_registration_collection_work(read)
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  assert_eq(
    prepare_program_check_source_resolution(owner).unwrap(),
    RegistrationFailed,
  )
  assert_true(owner.phase == SourceResolutionFailed && owner.work is None)
  let quote = owner.source_body_quote.unwrap()
  assert_eq(@context.source_registration_collection_work(read), prefix)
  assert_true(@context.source_registration_selection_work(read) > 0)
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok((before.0 + quote.0, before.1 + quote.0)),
  )
  assert_true(
    reconcile_program_check_source_resolution(owner) is Err(WrongPhase),
  )
  assert_true(
    @context.take_source_registration_result(read)
    is Some(Err(Selection({ kind: Unresolved, .. }))),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
