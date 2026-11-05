///|
// Actual checked Effect/nominal Request/Definition. Resource admission is the
// existing explicit ordinary Node fixture, not an installed Host or IO grant.
fn capture_recovery_originals() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  @publication.PublicationContract,
) {
  let (prepared, request, _) = effect_operation_plan_inputs()
  let compiled = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    request_program_module_manifests(),
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compiled,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "capture-recovery", "2026-10-25T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  (prepared, request, definition)
}

///|
test "cold capture grows SAME original Request reservation without compiler Source attempt or new Ledger" {
  let (prepared, request, definition) = capture_recovery_originals()
  let input = [81]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 0, 10000, 1000, 64,
  ).unwrap()
  let fixed = @resources.ledger_usage(owner.ledger)
  assert_true(fixed.reserved_retention_bytes > before.reserved_retention_bytes)
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 128, 10000, 1000, 64,
  ).unwrap()
  let held = @resources.ledger_usage(owner.ledger)
  assert_true(held.reserved_retention_bytes > fixed.reserved_retention_bytes)
  assert_true(physical_equal(original, owner.capacity))
  assert_eq(held.live_reservations, before.live_reservations)
  assert_eq(held.attempts, before.attempts)
  assert_eq(held.reserved_attempts, before.reserved_attempts)
  assert_eq(held.transferred_bytes, before.transferred_bytes)
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 128, 10000, 1000, 64,
  ).unwrap()
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 64, 10000, 1000, 64,
  ).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger), held)
  let copy = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(copy == request && !physical_equal(copy, request))
  assert_true(
    reserve_request_effect_capture_recovery(
      owner, input, copy, definition, 128, 10000, 1000, 64,
    )
    is Err(ForeignOriginal),
  )
  let copied_definition = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(definition),
    10000,
    1000,
    64,
  ).unwrap()
  assert_true(
    reserve_request_effect_capture_recovery(
      owner, input, request, copied_definition, 128, 10000, 1000, 64,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    reserve_request_effect_capture_recovery(
      owner,
      [81],
      request,
      definition,
      128,
      10000,
      1000,
      64,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    reserve_request_snapshot(owner, input, 16L, 2L) is Err(WrongPhase),
  )
  assert_true(
    borrow_request_program_plan_input(owner, input) is Err(WrongPhase),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), held)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(
    owner.input is None && owner.program_domain_compilation_inputs is None,
  )
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}

///|
test "capture grow capacity and original current refusals retain SAME funded cleanup" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [82]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 0, 10000, 1000, 64,
  ).unwrap()
  let original = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_effect_capture_recovery(
      owner, input, request, definition, 2000000, 10000, 1000, 64,
    )
    is Err(Capacity(_)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), original)
  abort_request_preparation_after_cleanup(owner).unwrap()
  // A refused absolute target is intentionally retained. Use a distinct real
  // parent for the independent current failure, not the already oversized
  // target that could refuse before reaching its original current callback.
  let current_input = [83]
  let calls = Ref(0)
  let current_owner = begin_request_preparation(
    request_parent_fixture(current_input, current=() => {
      calls.val += 1
      current.val
    }),
    current_input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_effect_capture_recovery(
    current_owner, current_input, request, definition, 0, 10000, 1000, 64,
  ).unwrap()
  let original = @resources.ledger_usage(current_owner.ledger)
  let before_calls = calls.val
  current.val = false
  assert_true(
    reserve_request_effect_capture_recovery(
      current_owner, current_input, request, definition, 128, 10000, 1000, 64,
    )
    is Err(Capacity(_)),
  )
  assert_true(calls.val > before_calls)
  assert_eq(@resources.ledger_usage(current_owner.ledger), original)
  assert_true(current_owner.phase == EffectCaptureRecovery)
  // Actual caller's physical children are closed before entering Abort.
  abort_request_preparation_after_cleanup(current_owner).unwrap()
  assert_true(current_owner.phase == Closed)
}

///|
test "live capture reserves and returns actual SAME adopted Effect Ledger without another Request" {
  let (prepared, request, definition) = capture_recovery_originals()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let quote = prepared_installed_effect_managed_requirements(plan)
  // Explicit original component envelope includes the selected recovery child;
  // no production policy/cap or normal constructor backing is changed here.
  quote[4] += 4000000L
  quote[5] += 4000000L
  let (input, initial, _, capacity) = effect_preparation_test_capacity(
    plan, quote,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = run.ledger.unwrap()
  let before = @resources.ledger_usage(ledger)
  let recovery = prepare_installed_effect_capture_recovery(
    run, prepared, request, definition, 10000, 1000, 64,
  ).unwrap()
  assert_true(
    recovery.ledger is Some(original) && physical_equal(original, ledger),
  )
  reserve_installed_effect_capture_recovery(recovery, 128).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_true(held.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(held.attempts, before.attempts)
  reserve_installed_effect_capture_recovery(recovery, 128).unwrap()
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_true(
    reserve_installed_effect_capture_recovery(recovery, 129)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  let material = recovery.material.unwrap()
  let full = request_effect_capture_recovery_capacity(
    128,
    @publication.publication_contract_json(definition).length(),
    10000,
    1000,
    64,
  ).unwrap()
  let scratch = @execution.execution_capacity_execution_bytes(full) -
    @execution.execution_capacity_retained_bytes(full)
  assert_true(scratch > 0L)
  complete_installed_effect_capture_recovery(recovery).unwrap()
  let completed = {
    ..held,
    reserved_execution_bytes: held.reserved_execution_bytes - scratch,
  }
  assert_eq(@resources.ledger_usage(ledger), completed)
  assert_true(physical_equal(recovery.material.unwrap(), material))
  complete_installed_effect_capture_recovery(recovery).unwrap()
  assert_eq(@resources.ledger_usage(ledger), completed)
  // The original retained output still prevents parent retirement. A later
  // SAME-extent read must fund its full workspace on the SAME original first.
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  let free = @resources.ledger_limits(ledger).execution_bytes -
    completed.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, free - scratch + 1L).unwrap()
  let pressured = @resources.ledger_usage(ledger)
  assert_true(
    reserve_installed_effect_capture_recovery(recovery, 128)
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), pressured)
  assert_true(physical_equal(recovery.material.unwrap(), material))
  @resources.settle_capacity(ledger, pressure).unwrap()
  reserve_installed_effect_capture_recovery(recovery, 128).unwrap()
  assert_eq(@resources.ledger_usage(ledger), held)
  complete_installed_effect_capture_recovery(recovery).unwrap()
  assert_eq(@resources.ledger_usage(ledger), completed)
  // Same Host has now retired its actual read/schema children, no Bool ACK
  // or new permission parameter can select another original here.
  retire_installed_effect_capture_recovery(recovery).unwrap()
  retire_installed_effect_capture_recovery(recovery).unwrap()
  assert_true(
    recovery.parent is None &&
    recovery.prepared is None &&
    recovery.request is None &&
    recovery.definition is None &&
    recovery.ledger is None &&
    recovery.fixed is None &&
    recovery.material is None,
  )
  assert_true(
    reserve_installed_effect_capture_recovery(recovery, 128) is Err(Retired),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
extern "js" fn capture_recovery_current_refusal() -> Unit =
  #| () => { throw new Error('OriginalRecoveryCurrentRefused'); }

///|
test "live capture completion preserves original peak on current and foreign Ledger refusal" {
  let (prepared, request, definition) = capture_recovery_originals()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[4] += 4000000L
  quote[5] += 4000000L
  let armed = Ref(false)
  let (input, initial, _, capacity) = effect_preparation_test_capacity(
    plan,
    quote,
    current=() => if armed.val { capture_recovery_current_refusal() },
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = run.ledger.unwrap()
  let recovery = prepare_installed_effect_capture_recovery(
    run, prepared, request, definition, 10000, 1000, 64,
  ).unwrap()
  reserve_installed_effect_capture_recovery(recovery, 128).unwrap()
  let held = @resources.ledger_usage(ledger)
  let (other_input, other_initial, foreign_ledger, other_capacity) = effect_preparation_test_capacity(
    plan, quote,
  )
  let other = begin_preparation_owned_installed_effect_managed_run(
    other_initial, other_input, other_capacity, prepared, request, plan,
  ).unwrap()
  let foreign_before = @resources.ledger_usage(foreign_ledger)
  let foreign = { ..recovery, ledger: Some(foreign_ledger), }
  assert_true(complete_installed_effect_capture_recovery(foreign) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
  armed.val = true
  assert_true(complete_installed_effect_capture_recovery(recovery) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), held)
  armed.val = false
  // Failed currentness keeps the original full peak until actual cleanup;
  // it never acknowledges output release or permits another read.
  retire_installed_effect_capture_recovery(recovery).unwrap()
  retire_installed_managed_run(run).unwrap()
  retire_installed_managed_run(other).unwrap()
}
