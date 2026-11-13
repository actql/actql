///|
// Actual portable Resource/Request/Check/compiler/Run ownership. The region
// and final owner-ACK are explicit nominal physical stand-ins; this does not
// allocate a VM, admit a platform profile or execute Python/native transport.
fn backed_request_initial_fixture(
  limits : @resources.LedgerLimits,
) -> (
  @resources.Ledger,
  @resources.BackedExecutionLiveAccess[Ref[Int], Ref[Int], Array[Int]],
  @resources.BackedPreparationAdmission[Array[Int]],
  Array[Int],
) {
  let bytes = limits.retained_bytes + limits.execution_bytes
  let root = @resources.create_ledger({
    ..limits,
    // The original shared-capacity reservation and delegation provision each
    // retain one attempt outside the complete delegated Request counters.
    attempts: limits.attempts + 2,
    retained_bytes: limits.retained_bytes + 4096L,
    execution_bytes: bytes + 4096L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, bytes).unwrap()
  let allocation = @resources.allocate_shared_capacity(capacity, bytes).unwrap()
  let provider = Ref(1)
  let child = Ref(2)
  let input = [3]
  let region = @resources.issue_backed_execution_region(
    capacity, allocation, provider,
  ).unwrap()
  let ticket = @resources.reserve_backed_execution_delegation(
    region,
    provider,
    child,
    { offset: 0L, length: bytes, payload_offset: 0L, payload_length: bytes, },
    @resources.ExclusiveWrite,
    limits,
    4096L,
    4096L,
  ).unwrap()
  let read = @resources.borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let access = @resources.issue_backed_execution_live_access(
    region, provider, child, ticket, read, input,
  ).unwrap()
  let projection = @resources.admit_backed_execution_live_child(access, input).unwrap()
  let initial = @resources.prepare_backed_preparation_admission(
    projection, input,
  ).unwrap()
  (root, access, initial, input)
}

///|
fn backed_request_fixture() -> (
  @resources.Ledger,
  @resources.BackedExecutionLiveAccess[Ref[Int], Ref[Int], Array[Int]],
  @resources.BackedPreparationAdmission[Array[Int]],
  ClientRequestPreparation[Array[Int]],
  Array[Int],
) {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let (root, access, initial, input) = backed_request_initial_fixture(limits)
  let parent = begin_backed_request_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  (root, access, initial, parent, input)
}

///|
fn backed_request_publication() -> (
  @checked.CheckEnvironment,
  @source_publication.PreparedPublishedQueryEnvironment,
) {
  let environment = catalog_domain_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  (environment, publication)
}

///|
test "portable backed Request keeps original compiler body Run and pending physical retirement" {
  let (root, access, initial, parent, input) = backed_request_fixture()
  let root_before = @resources.ledger_usage(root)
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let (environment, publication) = backed_request_publication()
  reserve_request_snapshot(parent, input, 64L, 32L).unwrap()
  parse_request_query_syntax(parent, input, "SELECT 7 AS n", @frontend.Sql).unwrap()
  |> ignore
  lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    None,
    public_primary=true,
  ).unwrap()
  |> ignore
  prepare_request_original_computation_check(
    parent,
    input,
    environment,
    publication,
    [],
    @publication_host.client_standard_program_preparation_limits(),
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  finish_request_computation_preparation(parent, input).unwrap()
  let prepared = parent.compiled_program.unwrap()
  let original_capacity = parent.program_capacity.unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  assert_true(
    physical_equal(parent.program_capacity.unwrap(), original_capacity),
  )
  let holder = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "portable-backed-request",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.source_free_preparation.unwrap(), plan))
  assert_true(parent.phase == Selected && parent.input is None)
  assert_true(
    installed_managed_run_compilation_original(run, prepared) is Some(_),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @resources.preparation_body_borrow_value(holder) is Some(original) &&
    physical_equal(original, prepared),
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  // Logical borrowers retiring does not acknowledge the physical original.
  // Preserve the existing exact Resource refusal, not a synthetic cleanup code.
  assert_true(retire_installed_managed_run(run) is Err(Resource(Unavailable)))
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(root), root_before)
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_true(installed_managed_run_compilation_original(run, prepared) is None)
}

///|
test "portable backed Request failed syntax retains original child and actual ACK dependency" {
  let (root, access, initial, parent, input) = backed_request_fixture()
  let before = @resources.ledger_usage(root)
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  reserve_request_snapshot(parent, input, 64L, 32L).unwrap()
  assert_true(
    parse_request_query_syntax(parent, input, "SELECT (", @frontend.Sql)
    is Err(_),
  )
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(Initial(_)),
  )
  assert_true(parent.phase == Retiring)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(root), before)
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.phase == Closed)
}

///|
test "portable backed Request foreign input cannot replace admission or release same parent's debit" {
  let (root, access, initial, parent, input) = backed_request_fixture()
  let before = @resources.ledger_usage(root)
  let child_before = @resources.ledger_usage(parent.ledger)
  assert_true(
    reserve_request_snapshot(parent, [3], 64L, 32L) is Err(ForeignOriginal),
  )
  assert_true(
    begin_backed_request_preparation(
      initial,
      input,
      client_local_resource_policy(),
    )
    is Err(Initial(_)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), child_before)
  assert_eq(@resources.ledger_usage(root), before)
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(Initial(_)),
  )
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "backed Request fixed prefix needs actual original controls not unused policy maxima" {
  let policy = client_local_resource_policy()
  let ceiling = client_local_preparation_initial_limits(policy).unwrap()
  let (controls, workspace) = client_request_preparation_control_capacity(
    policy,
  ).unwrap()
  assert_eq(workspace, 0L)
  let limits = {
    ..ceiling,
    retained_bytes: controls,
    execution_bytes: workspace,
  }
  let (root, access, initial, input) = backed_request_initial_fixture(limits)
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  // The actual delegated prefix covers its complete existing fixed quote.
  // Policy maximum is not a receipt for an unused 1GiB physical region.
  let parent = begin_backed_request_preparation(initial, input, policy).unwrap()
  let prefix = @resources.ledger_usage(parent.ledger)
  let root_before = @resources.ledger_usage(root)
  assert_eq(prefix.reserved_retention_bytes, controls)
  // Unbacked variable data still refuses BEFORE construction and remains on
  // the same child. No quote, logical ceiling or actual debit is reduced.
  let refusal = match reserve_request_snapshot(parent, input, 1L, 1L) {
    Err(SnapshotCapacityExceeded(Resource(RetentionLimit), value)) => value
    _ => fail("Expected original snapshot retention shortage with amounts")
  }
  let data = request_snapshot_data_bytes(1L, 1L).unwrap()
  assert_eq(refusal.phase, "request_snapshot")
  assert_eq(refusal.dimension, "retention")
  assert_eq(refusal.required_retention, controls + data)
  assert_eq(refusal.required_execution, data)
  assert_eq(refusal.available_retention, controls)
  assert_eq(refusal.available_execution, workspace)
  assert_eq(@resources.ledger_usage(parent.ledger), prefix)
  assert_eq(@resources.ledger_usage(root), root_before)
  assert_eq(parent.snapshot_units, 0L)
  assert_true(
    parent.submitted_intent is None && parent.compiled_program is None,
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(Initial(_)),
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "backed Request demand refuses one-short controls and preserves original physical cleanup" {
  let policy = client_local_resource_policy()
  let ceiling = client_local_preparation_initial_limits(policy).unwrap()
  let (controls, _) = client_request_preparation_control_capacity(policy).unwrap()
  let limits = {
    ..ceiling,
    retained_bytes: controls - 1L,
    execution_bytes: 0L,
  }
  let (_, access, initial, input) = backed_request_initial_fixture(limits)
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  assert_true(
    begin_backed_request_preparation(initial, input, policy)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(
    @resources.cleanup_backed_preparation_admission(initial) is Err(Unavailable),
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
}

///|
test "backed Request demand never upgrades an original grant beyond installed policy" {
  let policy = client_local_resource_policy()
  let ceiling = client_local_preparation_initial_limits(policy).unwrap()
  let limits = { ..ceiling, retained_bytes: ceiling.retained_bytes + 1L, }
  let (_, access, initial, input) = backed_request_initial_fixture(limits)
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  assert_true(
    begin_backed_request_preparation(initial, input, policy) is Err(Policy),
  )
  assert_true(
    @resources.cleanup_backed_preparation_admission(initial) is Err(Unavailable),
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
}

///|
test "backed Request demand retains exact funded snapshot and refuses unfunded syntax constructor" {
  let policy = client_local_resource_policy()
  let ceiling = client_local_preparation_initial_limits(policy).unwrap()
  let (controls, _) = client_request_preparation_control_capacity(policy).unwrap()
  let data = request_snapshot_data_bytes(8L, 1L).unwrap()
  let limits = {
    ..ceiling,
    retained_bytes: controls + data,
    execution_bytes: data,
  }
  let (root, access, initial, input) = backed_request_initial_fixture(limits)
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let parent = begin_backed_request_preparation(initial, input, policy).unwrap()
  reserve_request_snapshot(parent, input, 8L, 1L).unwrap()
  let retained = @resources.ledger_usage(parent.ledger)
  let root_before = @resources.ledger_usage(root)
  assert_eq(retained.reserved_retention_bytes, controls + data)
  assert_eq(retained.reserved_execution_bytes, data)
  assert_true(
    parse_request_query_syntax(parent, input, "SELECT 7 AS n", @frontend.Sql)
    is Err(Request(Capacity(_))),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), retained)
  assert_eq(@resources.ledger_usage(root), root_before)
  assert_true(parent.query_syntax is Some(query) && query.query is None)
  assert_eq(parent.snapshot_units, 8L)
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(Initial(_)),
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  @resources.retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
