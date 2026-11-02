///|
// Actual Request parent, JSON/Program and Parameter Source on one capacity.
// Borrowed input/callback backing is explicit component setup, not an ordinary
// Host first-entry supplier or a successful checked Program/Plan claim.
fn registration_parent_fixture(
  current? : () -> Bool = () => true,
  text? : String = request_check_wire,
  environment? : @checked.CheckEnvironment? = None,
  effect_limits? : @publication_host.ClientEffectComputationLimits? = None,
  supplied? : @decode.Cursor? = None,
  computation_limits? : (
    @publication_host.ClientProgramPreparationLimits,
    @publication_host.ClientEffectComputationLimits,
  )? = None,
  initial_limits? : @resources.LedgerLimits? = None,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  @stages.Source,
  Array[Int],
) raise {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input, current~, initial_limits~),
    input,
    client_local_resource_policy(),
  ).unwrap()
  request_check_source(parent, input, text~) |> ignore
  let limits = @publication_host.client_standard_program_preparation_limits().checking
  let selected_environment = match environment {
    Some(original) => original
    None => catalog_domain_environment()
  }
  let owner = match computation_limits {
    Some((program_limits, selected_effect_limits)) =>
      prepare_request_computation_check_preparation(
        parent,
        input,
        selected_environment,
        supplied,
        [],
        program_limits,
        selected_effect_limits,
      ).unwrap()
    None =>
      match effect_limits {
        None =>
          prepare_request_program_check_preparation(
            parent,
            input,
            selected_environment,
            supplied,
            [],
            limits,
          ).unwrap()
        Some(selected) =>
          prepare_request_effect_check_preparation(
            parent,
            input,
            selected_environment,
            supplied,
            [],
            selected,
          ).unwrap()
      }
  }
  let source = owner.arguments.unwrap().source_preparation.unwrap()
  prepare_program_check_input(owner).unwrap()
  prepare_program_check_prelude(owner).unwrap() |> ignore
  prepare_program_check_registry(owner).unwrap() |> ignore
  prepare_program_check_contents(owner).unwrap() |> ignore
  prepare_program_check_references(owner).unwrap() |> ignore
  prepare_program_check_policies(owner).unwrap() |> ignore
  prepare_program_check_values(owner).unwrap() |> ignore
  prepare_program_check_views(owner).unwrap() |> ignore
  prepare_program_check_carriers(owner).unwrap() |> ignore
  prepare_program_check_requests(owner).unwrap() |> ignore
  reconcile_program_check_requests(owner).unwrap()
  (parent, owner, source, input)
}

///|
test "original Request parent funds Source entry across both one-byte-short boundaries and preserves transferred custody" {
  assert_eq(program_check_source_entry_bytes, 2208L)
  assert_eq(program_check_source_retained_bytes, 1200L)
  for retention in [true, false] {
    let (parent, owner, source, input) = registration_parent_fixture()
    assert_true(physical_equal(owner.capacity, parent.capacity))
    let original = owner.check_registry.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - 2208L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - 2208L + 1L
      },
    ).unwrap()
    let result = prepare_program_check_source_registration(owner, source)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == SourceRegistrationQuoted)
    assert_true(owner.source_registration is None)
    assert_true(physical_equal(owner.registration_source.unwrap(), source))
    assert_true(
      @checked.parsed_check_registry_remaining_work(original) is Ok(_),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(before),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    prepare_program_check_source_registration(owner, source).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + 2208L, before.1 + 2208L)),
    )
    assert_true(
      @checked.parsed_check_registry_remaining_work(original)
      is Err(AlreadyConsumed),
    )
    let prepared = owner.source_registration.unwrap()
    let read = @checked.parsed_source_registration_read(prepared)
    assert_eq(@context.source_registration_phase(read), RegistrationCollect)
    assert_eq(@context.source_registration_collection_work(read), 0)
    assert_true(
      prepare_program_check_source_registration(owner, source)
      is Err(WrongPhase),
    )
    assert_true(take_program_check_registry(owner) is Err(WrongPhase))
    reconcile_program_check_source_registration(owner).unwrap()
    let held = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    assert_eq(held, (before.0 + 1200L, before.1 + 1200L))
    assert_true(
      physical_equal(
        take_program_check_source_registration(owner).unwrap(),
        prepared,
      ),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_eq(@context.source_registration_phase(read), RegistrationCollect)
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    assert_true(
      take_program_check_source_registration(owner) is Err(WrongPhase),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(held),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.ParameterSourceConstruction,
        0L,
      )
      is Err(AlreadyClaimed),
    )
    @context.clear_source_registration(read)
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(
        parent.capacity,
        input,
      ).unwrap(),
    )
    preparation_initial_cleanup(parent.initial).unwrap()
  }
}

///|
test "Source entry observes original current once and blocks synchronous retirement or duplicate construction" {
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, source, _) = registration_parent_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  action.val = Some(() => {
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if prepare_program_check_source_registration(owner, source)
      is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let before = calls.val
  prepare_program_check_source_registration(owner, source).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  let read = @checked.parsed_source_registration_read(
    owner.source_registration.unwrap(),
  )
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@context.source_registration_phase(read), RegistrationRetired)
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "stopping current refuses Source entry before registry consumption and does not refund prior work" {
  let stop = Ref(false)
  let calls = Ref(0)
  let (parent, owner, source, input) = registration_parent_fixture(current=() => {
    calls.val += 1
    !stop.val
  })
  let original = owner.check_registry.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let observed = calls.val
  stop.val = true
  assert_true(
    prepare_program_check_source_registration(owner, source)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_eq(calls.val - observed, 1)
  assert_true(owner.source_registration is None)
  assert_true(@checked.parsed_check_registry_remaining_work(original) is Ok(_))
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok(before),
  )
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.ParameterSourceConstruction,
      0L,
    )
    is Err(AlreadyClaimed),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "foreign Source cannot use funded entry as a fallback declaration reader" {
  let (parent, owner, _, _) = registration_parent_fixture()
  let foreign = @stages.prepare(catalog_current_program(), {
    max_parameters: 1,
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 1,
  }).unwrap()
  assert_true(
    prepare_program_check_source_registration(owner, foreign)
    is Err(SourceRegistration(SourceNotRetained)),
  )
  assert_true(owner.phase == Failed)
  assert_true(owner.source_registration is None)
  assert_true(
    @checked.parsed_check_registry_remaining_work(owner.check_registry.unwrap())
    is Err(AlreadyConsumed),
  )
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
