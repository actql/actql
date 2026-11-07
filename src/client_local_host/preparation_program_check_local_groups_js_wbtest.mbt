///|
fn registration_local_groups_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let (parent, owner, input) = registration_local_index_fixture(current~)
  inspect_program_check_source_local_index(owner).unwrap()
  prepare_program_check_source_local_index(owner).unwrap() |> ignore
  reconcile_program_check_source_local_index(owner).unwrap()
  (parent, owner, input)
}

///|
test "same parent funds both Local groups quotation and bodies without replaying original Index work" {
  assert_eq(program_source_local_groups_quote_bytes, 1248L)
  assert_eq(program_source_local_groups_driver_bytes, 368L)
  for retention in [true, false] {
    let (parent, owner, input) = registration_local_groups_fixture()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    let inputs = @context.source_registration_collected_inputs(read).unwrap()
    let collection = @context.source_registration_collection_work(read)
    let selection = @context.source_registration_selection_work(read)
    let index = @context.source_registration_local_index_usage(read)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 1248L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 1248L + 1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_local_groups(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      owner.phase == SourceLocalGroupsInitial && owner.source_body_quote is None,
    )
    assert_eq(@context.source_registration_phase(read), RegistrationLocal)
    @resources.settle_capacity(parent.ledger, short).unwrap()
    // Leave exactly the quote packet: body grow must refuse after quotation,
    // retaining the actual immutable quote for the original retry.
    let block_body = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 1248L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 1248L
      },
    ).unwrap()
    assert_true(
      prepare_program_check_source_local_groups(owner) is Err(Capacity(_)),
    )
    assert_true(owner.phase == SourceLocalGroupsQuoted)
    let quote = owner.source_body_quote.unwrap()
    assert_true(@context.source_registration_local_groups_work(read) is None)
    let quoted = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(quoted, (before.0 + 1248L, before.1 + 1248L))
    @resources.settle_capacity(parent.ledger, block_body).unwrap()
    let body_short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - quoted.0 - quote.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - quoted.1 - quote.0 + 1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_local_groups(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(physical_equal(owner.source_body_quote.unwrap(), quote))
    @resources.settle_capacity(parent.ledger, body_short).unwrap()
    assert_eq(
      prepare_program_check_source_local_groups(owner).unwrap(),
      RegistrationLocal,
    )
    // The authored fixture has two Stage groups and zero remote entries.
    assert_eq(@context.source_registration_local_groups_work(read), Some(2))
    assert_eq(@context.source_registration_local_index_usage(read), index)
    assert_eq(@context.source_registration_collection_work(read), collection)
    assert_eq(@context.source_registration_selection_work(read), selection)
    assert_true(
      physical_equal(
        inputs,
        @context.source_registration_collected_inputs(read).unwrap(),
      ),
    )
    assert_true(
      @context.source_registration_local_phase(read)
      is Some(LocalEnvironmentDeclaration),
    )
    assert_true(
      prepare_program_check_source_local_groups(owner) is Err(WrongPhase),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceLocalGroups,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_local_groups(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + quote.1, before.1 + quote.1)),
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
test "Local groups funding keeps original custody when current stops between quote and body grow" {
  let armed = Ref(false)
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = registration_local_groups_fixture(current=() => {
    if armed.val {
      calls.val += 1
      if action.val is Some(run) {
        run()
      }
      calls.val == 1
    } else {
      true
    }
  })
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if prepare_program_check_source_local_groups(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  armed.val = true
  assert_true(
    prepare_program_check_source_local_groups(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val, 2) // Two actual grows, no extra check-before-get.
  assert_eq(flags.val, 14)
  assert_true(
    owner.phase == SourceLocalGroupsQuoted && owner.source_body_quote is Some(_),
  )
  assert_eq(@context.source_registration_phase(read), RegistrationLocal)
  assert_true(@context.source_registration_local_groups_work(read) is None)
  assert_true(
    @context.source_registration_local_phase(read)
    is Some(LocalEnvironmentGroups),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
