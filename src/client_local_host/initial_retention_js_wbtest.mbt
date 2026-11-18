///|

///|

///|
test "successor acquired Source retention borrows its actual captured Program body beside the live Source child" {
  let (parent, input, prepared) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let source = begin_installed_managed_capture_read(run, 0).unwrap()
  let holder = managed_run_publication_body(run, prepared).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let retention = issue_program_initial_retention(
    run,
    prepared,
    request,
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  ).unwrap()
  check_original_retention_test_result(retention, "sha256:" + "5".repeat(64))
  assert_true(
    physical_equal(managed_run_publication_body(run, prepared).unwrap(), holder),
  )
  assert_true(
    run.captured_preparation is Some(original) && physical_equal(original, plan),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, before.attempts)
  let copied = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-request-capture-plan",
  ).unwrap()
  assert_eq(
    @publication_host.client_request_scope_cid(copied),
    @publication_host.client_request_scope_cid(request),
  )
  assert_false(physical_equal(copied, request))
  let held = @resources.ledger_usage(parent.ledger)
  assert_true(
    issue_program_initial_retention(
      run,
      prepared,
      copied,
      "sha256:" + "1".repeat(64),
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      10000,
      1000,
      32,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), held)
  // Publication cannot retire the still-owned Source child or fabricate its
  // physical ACK. The original child closes first, then the same Run body.
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  retire_installed_source_read(source).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "new malformed initial selection keeps full canonical identity width on the same Program owner" {
  let (run, initial, ledger) = initial_retention_program_fixture()
  let prepared = match run.preparation {
    Some(PureManaged(_, value)) => value
    _ => abort("fixture")
  }
  let holder = managed_run_publication_body(run, prepared).unwrap()
  let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let control = initial_retention_control_capacity().unwrap()
  let geometry = @publication.initial_result_retention_construction_geometry(
    "foreign",
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  ).unwrap()
  let body = effect_unit_publication_capacity(
    [("result_retention_policy", geometry)],
    @publication_host.client_request_scope_cid(run.request),
  ).unwrap()
  assert_true(
    issue_program_initial_retention(
      run,
      prepared,
      run.request,
      "foreign",
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      10000,
      1000,
      32,
    )
    is Err(
      PublicationRetention(@publication.InvalidField("retention_contract_cid"))
    ),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap().0,
    before.0 +
    @execution.execution_capacity_retained_bytes(control) +
    @execution.execution_capacity_retained_bytes(body),
  )
  assert_false(run.source_free_opening)
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_true(
    @resources.cleanup_node_preparation_admission(initial)
    is Err(AlreadyConsumed),
  )
}

///|
test "new initial Program body exact and one-short grow preserve the same earlier prefix" {
  let (run, initial, ledger) = initial_retention_program_fixture()
  let prepared = match run.preparation {
    Some(PureManaged(_, value)) => value
    _ => abort("fixture")
  }
  let holder = managed_run_publication_body(run, prepared).unwrap()
  let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let control = initial_retention_control_capacity().unwrap()
  let geometry = @publication.initial_result_retention_construction_geometry(
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  ).unwrap()
  let body = effect_unit_publication_capacity(
    [("result_retention_policy", geometry)],
    "sha256:" + "1".repeat(64),
  ).unwrap()
  let prefix = @execution.execution_capacity_retained_bytes(control)
  let total = prefix + @execution.execution_capacity_retained_bytes(body)
  let limits = @resources.ledger_limits(ledger)
  let usage = @resources.ledger_usage(ledger)
  let short = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    total +
    1L,
    0L,
  ).unwrap()
  assert_true(
    issue_initial_program_fixture(run)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap().0,
    before.0 + prefix,
  )
  @resources.settle_capacity(ledger, short).unwrap()
  let usage = @resources.ledger_usage(ledger)
  let exact = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    total,
    0L,
  ).unwrap()
  check_original_retention_test_result(
    issue_initial_program_fixture(run).unwrap(),
    "sha256:" + "5".repeat(64),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap().0,
    before.0 + prefix + total,
  )
  @resources.settle_capacity(ledger, exact).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_true(
    @resources.cleanup_node_preparation_admission(initial)
    is Err(AlreadyConsumed),
  )
}

///|
test "new initial original current loss refuses both owners without exposing a successful contract" {
  let alive = Ref(true)
  let (run, initial, ledger) = initial_retention_program_fixture(current=() => {
    alive.val
  })
  let before = @resources.ledger_usage(ledger)
  alive.val = false
  assert_true(issue_initial_program_fixture(run) is Err(Capacity(_)))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(run.source_free_opening)
  retire_installed_managed_run(run).unwrap()
  assert_true(
    @resources.cleanup_node_preparation_admission(initial)
    is Err(AlreadyConsumed),
  )
  alive.val = true
  let original = effect_publication_values_original(current=() => alive.val)
  let before = @resources.ledger_usage(original.parent.ledger)
  alive.val = false
  assert_true(
    issue_initial_effect_fixture(original) is Err(Run(Preparation(_))),
  )
  assert_eq(@resources.ledger_usage(original.parent.ledger), before)
  assert_false(original.run.effect_operation_opening)
  close_effect_publication_values(original)
}

///|
// Reuse the actual Node Resource/manager fixture recipe. Only its explicit
// test Program backing is synthetic; the reservation/current/cleanup are real.
fn initial_retention_program_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientInstalledManagedRun,
  @resources.NodePreparationAdmission[Array[Int]],
  @resources.Ledger,
) {
  let input = [1]
  let initial = request_parent_fixture(input, current~)
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let prepared = result_envelope_fixture()
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    1000000L,
    0L,
    max_borrowers=3,
  ).unwrap()
  let plan = request_program_installed_plan(prepared)
  @resources.complete_preparation_capacity(
    capacity, input, prepared, 1000000L, 0L,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "initial-retention",
  ).unwrap()
  let run = begin_preparation_owned_installed_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  (run, initial, ledger)
}

///|
fn issue_initial_program_fixture(
  run : ClientInstalledManagedRun,
) -> Result[
  @publication.PublicationContract,
  ClientClosedValuesPreparationIssue,
] {
  let prepared = match run.preparation {
    Some(PureManaged(_, value)) => value
    _ => abort("fixture original missing")
  }
  issue_program_initial_retention(
    run,
    prepared,
    run.request,
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  )
}

///|
fn issue_initial_effect_fixture(
  original : EffectPublicationValuesOriginal,
) -> Result[@publication.PublicationContract, ClientEffectUnitPreparationIssue] {
  issue_installed_effect_initial_retention(
    original.run,
    original.prepared,
    original.request,
    original.plan,
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  )
}

///|
test "initial Program retention uses its own body and refuses one-short before measurement" {
  let (run, initial, ledger) = initial_retention_program_fixture()
  let prepared = match run.preparation {
    Some(PureManaged(_, value)) => value
    _ => abort("fixture")
  }
  let holder = managed_run_publication_body(run, prepared).unwrap()
  let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let control = initial_retention_control_capacity().unwrap()
  let usage = @resources.ledger_usage(ledger)
  let limits = @resources.ledger_limits(ledger)
  let pressure = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    @execution.execution_capacity_retained_bytes(control) +
    1L,
    0L,
  ).unwrap()
  assert_true(
    issue_initial_program_fixture(run)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder),
    Ok(before),
  )
  assert_false(run.source_free_opening)
  @resources.settle_capacity(ledger, pressure).unwrap()
  let value = issue_initial_program_fixture(run).unwrap()
  check_original_retention_test_result(value, "sha256:" + "5".repeat(64))
  assert_true(
    physical_equal(managed_run_publication_body(run, prepared).unwrap(), holder),
  )
  let foreign = result_envelope_fixture()
  let held = @resources.ledger_usage(ledger)
  assert_true(
    issue_program_initial_retention(
      run,
      foreign,
      run.request,
      "sha256:" + "1".repeat(64),
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      10000,
      1000,
      32,
    )
    is Err(ForeignOriginal),
  )
  let enormous = @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 9223372036854775807L,
    workspace_bytes: 0L,
  }).unwrap()
  assert_true(
    reserve_program_retention_capacity(run, prepared, enormous) is Err(Policy),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  retire_installed_managed_run(run).unwrap()
  assert_true(
    issue_initial_program_fixture_retired(run, prepared) is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  // The original admission was consumed by the actual Run transfer. Its
  // same Run retirement above owns cleanup; no second cleanup ACK exists.
  assert_true(
    @resources.cleanup_node_preparation_admission(initial)
    is Err(AlreadyConsumed),
  )
}

///|
fn issue_initial_program_fixture_retired(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication.PublicationContract,
  ClientClosedValuesPreparationIssue,
] {
  issue_program_initial_retention(
    run,
    prepared,
    run.request,
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  )
}

///|
test "initial Effect retention retains failed-prefix responsibility then succeeds at exact original capacity" {
  let original = effect_publication_values_original()
  let holder = effect_unit_publication_body(
    original.run,
    original.plan,
    original.request,
  ).unwrap()
  let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let control = initial_retention_control_capacity().unwrap()
  let geometry = @publication.initial_result_retention_construction_geometry(
    "sha256:" + "1".repeat(64),
    "sha256:" + "5".repeat(64),
    "2026-11-18T01:00:00.000Z",
    "2026-11-18T02:00:00.000Z",
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "2".repeat(64),
    "2026-11-25T00:00:00.000Z",
    "sha256:" + "3".repeat(64),
    10000,
    1000,
    32,
  ).unwrap()
  let body = effect_unit_publication_capacity(
    [("result_retention_policy", geometry)],
    "sha256:" + "1".repeat(64),
  ).unwrap()
  let prefix_r = before.0 +
    @execution.execution_capacity_retained_bytes(control)
  let next_r = prefix_r + @execution.execution_capacity_retained_bytes(body)
  let usage = @resources.ledger_usage(original.parent.ledger)
  let limits = @resources.ledger_limits(original.parent.ledger)
  let pressure = @resources.reserve_capacity(
    original.parent.ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    (next_r - before.0) +
    1L,
    0L,
  ).unwrap()
  assert_true(
    issue_initial_effect_fixture(original)
    is Err(Run(Preparation(Resource(RetentionLimit)))),
  )
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap().0,
    prefix_r,
  )
  assert_false(original.run.effect_operation_opening)
  @resources.settle_capacity(original.parent.ledger, pressure).unwrap()
  // A distinct constructor call is independently charged: its earlier failed
  // measuring prefix remains live rather than being refunded or reused.
  let usage = @resources.ledger_usage(original.parent.ledger)
  let exact = @resources.reserve_capacity(
    original.parent.ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    (next_r - before.0),
    0L,
  ).unwrap()
  let value = issue_initial_effect_fixture(original).unwrap()
  check_original_retention_test_result(value, "sha256:" + "5".repeat(64))
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap().0,
    prefix_r + (next_r - before.0),
  )
  @resources.settle_capacity(original.parent.ledger, exact).unwrap()
  assert_true(
    issue_installed_effect_initial_retention(
      original.run,
      original.prepared,
      original.request,
      { ..original.plan, },
      "sha256:" + "1".repeat(64),
      "sha256:" + "5".repeat(64),
      "2026-11-18T01:00:00.000Z",
      "2026-11-18T02:00:00.000Z",
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "2".repeat(64),
      "2026-11-25T00:00:00.000Z",
      "sha256:" + "3".repeat(64),
      10000,
      1000,
      32,
    )
    is Err(Run(ForeignOriginal)),
  )
  close_effect_publication_values(original)
}

///|
test "initial Program and Effect constructors retain existing current and reentry latches" {
  let action : Ref[() -> Unit] = Ref(() => ())
  let (run, initial, ledger) = initial_retention_program_fixture(current=() => {
    (action.val)()
    true
  })
  let blocked = Ref(false)
  action.val = () => {
    blocked.val = issue_initial_program_fixture(run) is Err(WrongPhase)
  }
  issue_initial_program_fixture(run).unwrap() |> ignore
  assert_true(blocked.val)
  action.val = () => ()
  retire_installed_managed_run(run).unwrap()
  // The original admission was consumed by the actual Run transfer. Its
  // same Run retirement above owns cleanup; no second cleanup ACK exists.
  assert_true(
    @resources.cleanup_node_preparation_admission(initial)
    is Err(AlreadyConsumed),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  let original = effect_publication_values_original(current=() => {
    (action.val)()
    true
  })
  blocked.val = false
  action.val = () => {
    blocked.val = issue_initial_effect_fixture(original)
      is Err(Run(AlreadyBound))
  }
  issue_initial_effect_fixture(original).unwrap() |> ignore
  assert_true(blocked.val)
  action.val = () => ()
  close_effect_publication_values(original)
}
