///|
// Actual authored keyed Source/SERIALIZE Program enters the original Request
// checker and compiler. Provider, Store and physical backing are not executed.
fn request_content_compile_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  (
    SplitKeyedContentLimitsFixture,
    String,
    @checked.CheckEnvironment,
    @row_source_host.RowDeclaration,
  ),
) raise {
  let original = split_keyed_content_limits_fixture()
  let (parent, child, _, input) = registration_parent_fixture(
    text=original.1,
    environment=Some(original.2),
    current~,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original keyed Content check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  (parent, input, prepared, original)
}

///|
fn request_content_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  ClientInstalledManagedKeyedPreparation,
  @publication_host.ClientRequestIdentity,
) raise {
  let (parent, input, prepared, original) = request_content_compile_fixture(
    current~,
  )
  let borrowed = borrow_request_content_plan_input(parent, input).unwrap()
  // Independent Plan/Request/optional compiler link inventory under the
  // pinned logical tariff: 3 headers16 + 4 references8 + 3 words8 =104 bytes.
  let quote = parent.program_plan_quote.unwrap()
  let funded = request_preparation_accounting(parent)
  assert_eq(funded.4, quote.0 + 104L)
  assert_eq(funded.5, quote.1 + 104L)
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let keyed = @publication_host.select_client_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  let (stage, unit, _) = @publication_host.client_keyed_direct_acquisition_coordinates(
    keyed,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    stage,
    unit,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let acquisition = @row_source_host.prepare_row_acquisition(
    original.3,
    requirement,
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  let direct = installed_row_capture_capacity(acquisition).unwrap()
  let occurrences = @publication_host.prepared_client_serialization_occurrences(
    prepared,
  )
  let (task, step) = occurrences[0]
  let (_, execution, measurement) = client_local_execution_limits(max_rows=3)
  let prefix = client_acquired_serialization_prefix_capacity(
    prepared,
    task,
    step,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  let selected = prepare_installed_managed_keyed_content(
    prepared,
    direct,
    keyed,
    original.3,
    original_keyed_child_limits(),
    [8192L, 8192L],
    [4096L, 4096L],
    4096,
    1000000,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    task,
    step,
    @execution.execution_capacity_retained_bytes(prefix),
    @execution.execution_capacity_execution_bytes(prefix),
  ).unwrap()
  assert_false(@resources.return_preparation_body_borrow(borrowed).unwrap())
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-request-keyed-content",
  ).unwrap()
  (parent, input, prepared, selected, request)
}

///|
test "same Request Content retires only its unused first census and preserves spent input work" {
  let (parent, input, prepared, selected, request) = request_content_fixture()
  let capacity = parent.program_capacity.unwrap()
  let census = @resources.preparation_capacity_inventory_original(
    capacity, input,
  ).unwrap()
  assert_true(@resources.original_ledger_inventory_available(census))
  let io = @resources.begin_preparation_io(capacity, input, 2L).unwrap()
  @resources.charge_preparation_io(io, 1L).unwrap()
  @resources.finish_preparation_io_after_cleanup(io).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_eq(before.attempts, 1)
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(
    run.ledger is Some(ledger) && physical_equal(ledger, parent.ledger),
  )
  // Initial borrower slots are not business Source/Content capacity. No
  // reservation, consumed work or attempt is refunded by metadata disposal.
  assert_false(@resources.original_ledger_inventory_live(census))
  let adopted = @resources.ledger_usage(parent.ledger)
  assert_eq(adopted.attempts, before.attempts)
  assert_eq(adopted.planning_work, before.planning_work)
  assert_true(
    check_installed_managed_run_binding(run, prepared, request) is Ok(_),
  )
  retire_installed_managed_run(run).unwrap()
  let retired = @resources.ledger_usage(parent.ledger)
  assert_eq(retired.live_reservations, 0)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.attempts, before.attempts)
  assert_eq(retired.planning_work, before.planning_work)
}

///|
test "Content cannot discard a bound original census or replace its cleanup owner" {
  let (parent, input, _, selected, request) = request_content_fixture()
  let capacity = parent.program_capacity.unwrap()
  let census = @resources.preparation_capacity_inventory_original(
    capacity, input,
  ).unwrap()
  @resources.claim_original_ledger_run_binding(census, parent.ledger).unwrap()
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    begin_request_content_managed_run(parent, request)
    is Err(Preparation(WorkActive)),
  )
  assert_true(parent.phase == ProgramBodyReady && parent.input is Some(_))
  assert_true(@resources.original_ledger_inventory_live(census))
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  // This explicit component owns no physical children. The existing original
  // census finish, not Content metadata disposal, acknowledges its cleanup.
  assert_eq(
    @resources.finish_original_ledger_inventory(parent.ledger, true),
    Ok(true),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Program inventory borrow can select Content without replacing its grown extent or releasing either original" {
  let calls = Ref(0)
  let (parent, input, prepared, _) = request_content_compile_fixture(current=() => {
    calls.val += 1
    true
  })
  let program = borrow_request_program_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let quote = parent.program_plan_quote.unwrap()
  let (r, e) = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  // Independent Plan/Request/compiler link inventory:3 headers,4 refs,3 words
  // at the pinned16/8/8-byte tariff, not a value read from the product quote.
  let links = 3L * 16L + 4L * 8L + 3L * 8L
  // Independent occupied test extents, deliberately greater than those links.
  // They do not stand in for a provider's full domain recipe.
  @resources.reserve_working_preparation_phase(
    capacity,
    input,
    r + 129L,
    e + 257L,
  ).unwrap()
  let before = calls.val
  let content = borrow_request_content_plan_input(parent, input).unwrap()
  assert_eq(calls.val, before + 1)
  assert_true(parent.phase == ContentPlanReserved)
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_eq(parent.program_plan_quote.unwrap(), quote)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((r + 129L + links, e + 257L + links)),
  )
  for holder in [program, content] {
    assert_true(
      @resources.preparation_body_borrow_value(holder) is Some(original) &&
      physical_equal(original, prepared),
    )
  }
  assert_false(@resources.return_preparation_body_borrow(program).unwrap())
  let charged = request_preparation_accounting(parent)
  let second = borrow_request_content_plan_input(parent, input).unwrap()
  assert_eq(request_preparation_accounting(parent), charged)
  assert_true(
    borrow_request_program_plan_input(parent, input) is Err(WrongPhase),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_false(@resources.return_preparation_body_borrow(content).unwrap())
  assert_true(@resources.ledger_usage(parent.ledger).live_reservations > 0)
  assert_true(@resources.return_preparation_body_borrow(second).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Content selection refusal preserves the outstanding Program borrower and charged extent" {
  let calls = Ref(0)
  let (parent, input, prepared, _) = request_content_compile_fixture(current=() => {
    calls.val += 1
    true
  })
  let program = borrow_request_program_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let (_, e) = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  // Leave one short link carrier's worth of room, without allocating DATA or
  // changing the original logical limit. This is only a refusal control.
  let r = @resources.ledger_limits(parent.ledger).retained_bytes - 32L
  @resources.reserve_working_preparation_phase(capacity, input, r, e).unwrap()
  let before = request_preparation_accounting(parent)
  let observed = calls.val
  assert_true(
    borrow_request_content_plan_input(parent, [1]) is Err(ForeignOriginal),
  )
  assert_eq(calls.val, observed)
  assert_true(
    borrow_request_content_plan_input(parent, input)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_eq(calls.val, observed + 1)
  assert_true(parent.phase == ProgramPlanReserved)
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(
    @resources.preparation_body_borrow_value(program) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(@resources.return_preparation_body_borrow(program).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "keyed Content keeps its actual checked Plan on the same Request through adoption and borrower retirement" {
  let calls = Ref(0)
  let (parent, input, prepared, selected, request) = request_content_fixture(current=() => {
    calls.val += 1
    true
  })
  let original = parent.program_capacity.unwrap()
  let before = request_preparation_accounting(parent)
  let before_complete = calls.val
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  assert_eq(calls.val, before_complete + 1)
  assert_true(physical_equal(parent.program_capacity.unwrap(), original))
  assert_true(
    parent.program_content is KeyedContent(plan, _) &&
    physical_equal(plan, selected),
  )
  assert_true(
    parent.program_source_free is None && parent.program_captured is None,
  )
  let completed = request_preparation_accounting(parent)
  assert_eq(completed, before)
  let holder = borrow_request_program_preparation(parent).unwrap()
  let before_adoption = calls.val
  let copied_request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "different-request-content",
  ).unwrap()
  assert_true(
    begin_request_content_managed_run(parent, copied_request)
    is Err(ForeignOriginal),
  )
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_eq(calls.val, before_adoption + 1)
  assert_true(parent.phase == Selected && parent.input is None)
  assert_true(
    run.content is KeyedContent(plan, _) && physical_equal(plan, selected),
  )
  assert_true(
    run.preparation is Some(PreparationContentManaged(_, original)) &&
    physical_equal(original, prepared),
  )
  assert_true(
    run.ledger is Some(ledger) && physical_equal(ledger, parent.ledger),
  )
  assert_eq(request_preparation_accounting(parent).0, completed.0)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @resources.preparation_body_borrow_value(holder) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(run.content is NoContent)
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_true(run.ledger is None && run.preparation_retirement is None)
}

///|
test "keyed Content refuses foreign prepared Plan without consuming the original Request" {
  let (parent, input, prepared, selected, request) = request_content_fixture()
  let (foreign, _, _, other, _) = request_content_fixture()
  let before = request_preparation_accounting(parent)
  assert_true(
    complete_request_content_preparation(parent, [1], request, selected)
    is Err(ForeignOriginal),
  )
  assert_true(
    complete_request_content_preparation(parent, input, request, other)
    is Err(ForeignOriginal),
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(
    parent.phase == ContentPlanReserved && parent.program_content is NoContent,
  )
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  assert_true(
    complete_request_content_preparation(parent, input, request, selected)
    is Err(WrongPhase),
  )
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(
    check_installed_managed_run_binding(run, prepared, request) is Ok(_),
  )
  retire_installed_managed_run(run).unwrap()
  abort_request_preparation_after_cleanup(foreign).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(
    @resources.ledger_usage(foreign.ledger).reserved_retention_bytes,
    0L,
  )
}

///|
test "keyed Content constructor borrows preserve its quoted link and keep cancellation on the same owner" {
  let (parent, input, prepared, _, _) = request_content_fixture()
  let before = request_preparation_accounting(parent)
  let held = borrow_request_content_plan_input(parent, input).unwrap()
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(
    borrow_request_program_plan_input(parent, input) is Err(WrongPhase),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(parent.phase == Retiring && parent.input is Some(_))
  assert_true(
    parent.compiled_program is None && parent.program_content is NoContent,
  )
  assert_true(
    @resources.preparation_body_borrow_value(held) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  assert_true(@resources.return_preparation_body_borrow(held).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.phase == Closed)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "keyed Content adoption fences current reentry once without selecting another purpose" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let calls = Ref(0)
  let flags = Ref(0)
  let (parent, input, _, selected, request) = request_content_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  action.val = Some(() => {
    if begin_request_content_managed_run(parent, request)
      is Err(ForeignOriginal) {
      flags.val += 1
    }
    if borrow_request_program_preparation(parent) is Err(WrongPhase) {
      flags.val += 2
    }
    if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let before = calls.val
  let run = begin_request_content_managed_run(parent, request).unwrap()
  action.val = None
  assert_eq(calls.val, before + 1)
  assert_eq(flags.val, 7)
  assert_true(
    run.content is KeyedContent(original, _) &&
    physical_equal(original, selected),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
