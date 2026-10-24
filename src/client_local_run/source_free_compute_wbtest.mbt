///|
fn source_free_root() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 1000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
}

///|
fn source_free_shared_host(
  plan : LocalRunPlan,
  root : @resources.Ledger,
) -> Result[LocalComputeHost, LocalComputeIssue] raise {
  configure_source_free_local_compute_on_ledger(
    plan,
    root,
    registered_installed_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    Some(@identity.stringify_value(registered_ordered(), 100000, 10000, 100)),
  )
}

///|
test "source-free shared root retains the original ledger and requires activation" {
  let original = plan(prepared(@input.Aql("SELECT 1 AS n")), "source-free-root")
  let root = source_free_root()
  // The same reservation made by the installed Wasm Host. This test does
  // not allocate a physical module or establish whole-process accounting.
  let wasm = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let before = @resources.ledger_usage(root)
  let host = source_free_shared_host(original, root).unwrap()
  let run = local_compute_run(host)
  assert_true(physical_equal(@strategy.captured_dag_ledger(run), root))
  // One offer: seven slots, three lines, and seven line-slot entries.
  // One-task strategy: task + offer + assignment + task + two duration cells.
  // The import/export lines each add a slot to the five compute slots.
  assert_eq(@resources.ledger_usage(root), {
    ..before,
    planning_work: before.planning_work + (7 + 3 + 7) + (1 + 1 + 1 + 1 + 2),
  })
  assert_true(@strategy.captured_task_activation_required(run))
  assert_false(@strategy.captured_task_completed(run, 0))
  assert_eq(@host.prepared_client_acquisition_count(original.prepared), 0)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 16777216L)
  @resources.close_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 16777216L)
  @resources.settle_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
}

///|
test "source-free shared root executes SELECT one with original bounded task owners" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = plan(input, "source-free-select")
  let root = source_free_root()
  let wasm = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let host = source_free_shared_host(original, root).unwrap()
  let run = local_compute_run(host)
  let current = account(Allow)
  // Independent start facts exercise the existing Owner. They are not a
  // public Host admission receipt or a persisted physical-start observation.
  let start = compute_start(host)
  let operations = start_local_compute_task(
      host,
      start,
      [],
      permit(input, current),
      current,
      tuple(),
      context_cid(),
    )
    .unwrap()
    .unwrap()
  assert_eq(operations.inputs.length(), 0)
  let mut executed = false
  for _ in 0..<1000 {
    let progress = (operations.advance)(1).unwrap()
    assert_true(progress.work >= 0L && progress.work <= 1L)
    if progress.complete {
      executed = true
      break
    }
  }
  assert_true(executed)
  let available = Ref(true)
  (operations.prepare_finalization)(0, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  let mut finalized = false
  for _ in 0..<1000 {
    if (operations.advance_finalization)(1).unwrap().complete {
      finalized = true
      break
    }
  }
  assert_true(finalized)
  (operations.settle)().unwrap()
  (operations.complete)(0, operations.storage_bytes, () => available.val).unwrap()
  |> ignore
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"n\":1}")
  assert_true(@resources.ledger_usage(root).held_bytes > 0L)
  assert_true(
    @resources.ledger_usage(root).reserved_execution_bytes >= 16777216L,
  )
  available.val = false
  (operations.close)()
  @strategy.close_captured_task_output(run, 0)
  assert_true((operations.cleanup_refresh)())
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let released = @resources.ledger_usage(root)
  assert_eq(released.held_bytes, 0L)
  assert_eq(released.reserved_retention_bytes, 0L)
  assert_eq(released.reserved_execution_bytes, 16777216L)
  @resources.close_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 16777216L)
  @resources.settle_shared_capacity(wasm).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
}

///|
test "source-free shared root cannot bypass an exhausted original execution budget" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = plan(input, "source-free-capacity")
  let root = source_free_root()
  let occupied = @resources.reserve_shared_capacity(root, 536870912L).unwrap()
  // Original offer selection rejects the exhausted root while configuring
  // the Host, before any task can be activated or acquire a Source.
  assert_true(source_free_shared_host(original, root) is Err(Configuration))
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 536870912L)
  assert_eq(@resources.ledger_usage(root).held_bytes, 0L)
  @resources.close_shared_capacity(occupied).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 536870912L)
  @resources.settle_shared_capacity(occupied).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
}

///|
test "compute configuration rechecks original account subject scope and context" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = plan(input, "source-free-current")
  let allow = account(Allow)
  let original_permit = permit(input, allow)
  assert_true(
    authorize_local_compute_configuration(
      original,
      original_permit,
      allow,
      tuple(),
      context_cid(),
    )
    is Ok(_),
  )
  let denied = account(Deny)
  assert_true(
    authorize_local_compute_configuration(
      original,
      original_permit,
      denied,
      tuple(),
      context_cid(),
    )
    is Err(AuthorizationMismatch),
  )
  assert_true(
    authorize_local_compute_configuration(
      original,
      original_permit,
      allow,
      { ..tuple(), operation: "read", },
      context_cid(),
    )
    is Err(AuthorizationMismatch),
  )
  assert_true(
    authorize_local_compute_configuration(
      original,
      original_permit,
      allow,
      tuple(),
      "sha256:" + "d".repeat(64),
    )
    is Err(AuthorizationMismatch),
  )
  let other = prepared(@input.Aql("SELECT 2 AS n"))
  assert_true(
    authorize_local_compute_configuration(
      original,
      permit(other, allow),
      allow,
      tuple(),
      context_cid(),
    )
    is Err(AuthorizationMismatch),
  )
}

///|
test "source-free compute cannot bind a foreign original physical start" {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let original = plan(input, "source-free-bound")
  let other = plan(input, "source-free-other")
  let root = source_free_root()
  let host = source_free_shared_host(original, root).unwrap()
  let foreign_host = source_free_shared_host(other, root).unwrap()
  let foreign_start = compute_start(foreign_host)
  // Extracting the accepted start uses the exact original Owner, not a new Bool.
  let current = account(Allow)
  let accepted = confirm_local_run_physical_start(
    other,
    other.request,
    @publication.publication_contract_identity(other.definition),
    true,
    true,
    false,
    false,
    permit(input, current),
    current,
    tuple(),
    context_cid(),
  ).unwrap()
  assert_true(
    bind_local_compute_start(host, accepted) is Err(StartNotPermitted),
  )
  assert_false(physical_equal(foreign_start.host, host))
  for value in [host, foreign_host] {
    let run = local_compute_run(value)
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
  }
}
