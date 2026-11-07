///|
fn registration_pipeline_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let (parent, owner, source, input) = registration_parent_fixture(current~)
  prepare_program_check_source_registration(owner, source).unwrap()
  inspect_program_check_source_collection(owner).unwrap()
  prepare_program_check_source_collection(owner).unwrap() |> ignore
  inspect_program_check_source_resolution(owner).unwrap()
  prepare_program_check_source_resolution(owner).unwrap() |> ignore
  reconcile_program_check_source_resolution(owner).unwrap()
  (parent, owner, input)
}

///|
test "same parent funds both pipeline quote and original Stage arrays without replaying selection" {
  assert_eq(program_source_pipeline_quote_bytes, 2864L)
  assert_eq(program_source_pipeline_driver_bytes, 160L)
  assert_eq(program_source_pipeline_driver_retained_bytes, 32L)
  for retention in [true, false] {
    let (parent, owner, input) = registration_pipeline_fixture()
    let original = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(original)
    let inputs = @context.source_registration_collected_inputs(read).unwrap()
    let collection = @context.source_registration_collection_work(read)
    let selection = @context.source_registration_selection_work(read)
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 2864L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 2864L + 1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_pipeline(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      owner.phase == SourcePipelineInitial && owner.source_body_quote is None,
    )
    assert_eq(@context.source_registration_phase(read), RegistrationPipeline)
    @resources.settle_capacity(parent.ledger, short).unwrap()
    // Leave exactly the quote packet: body grow must refuse after quotation,
    // retaining the actual immutable quote for the original retry.
    let block_body = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 2864L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 2864L
      },
    ).unwrap()
    assert_true(
      prepare_program_check_source_pipeline(owner) is Err(Capacity(_)),
    )
    assert_true(owner.phase == SourcePipelineQuoted)
    let quote = owner.source_body_quote.unwrap()
    assert_eq(@context.source_registration_pipeline_work(read), 0)
    let quoted = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(quoted, (before.0 + 2864L, before.1 + 2864L))
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
    let refused = prepare_program_check_source_pipeline(owner)
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
      prepare_program_check_source_pipeline(owner).unwrap(),
      RegistrationLocal,
    )
    // The authored fixture has two Stage groups and zero remote entries.
    assert_eq(@context.source_registration_pipeline_work(read), 2)
    assert_eq(@context.source_registration_collection_work(read), collection)
    assert_eq(@context.source_registration_selection_work(read), selection)
    assert_true(
      physical_equal(
        inputs,
        @context.source_registration_collected_inputs(read).unwrap(),
      ),
    )
    assert_true(@context.source_registration_local_phase(read) is None)
    assert_true(prepare_program_check_source_pipeline(owner) is Err(WrongPhase))
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourcePipelineRegistration,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_pipeline(owner).unwrap()
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
test "pipeline funding keeps original custody when current stops between quote and body grow" {
  let armed = Ref(false)
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = registration_pipeline_fixture(current=() => {
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
    if prepare_program_check_source_pipeline(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  armed.val = true
  assert_true(
    prepare_program_check_source_pipeline(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(calls.val, 2) // Two actual grows, no extra check-before-get.
  assert_eq(flags.val, 14)
  assert_true(
    owner.phase == SourcePipelineQuoted && owner.source_body_quote is Some(_),
  )
  assert_eq(@context.source_registration_phase(read), RegistrationPipeline)
  assert_eq(@context.source_registration_pipeline_work(read), 0)
  assert_true(@context.source_registration_local_phase(read) is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
