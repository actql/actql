///|
// Actual private ABI calls with an original instance/task lookup. No current
// Run/Compute is issued here; the existing release harness denies physical I/O.
fn task_drive_current_refusal_case(pending_case : Bool) -> Unit raise {
  let root = @resources.create_ledger({
    planning_work: 100,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 65536L,
    retained_bytes: 65536L,
    execution_bytes: 16781312L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 4096L, 16, 1048576).unwrap()
  let nonce = 7143L
  assert_eq(
    install_buffer_instance(
      nonce,
      root,
      capacity,
      None,
      pool,
      16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(nonce).unwrap()
  let record : StoredManagedTask = {
    compute: 1,
    current_configuration: 2,
    task: 0,
    invoked: false,
    pending: false,
    closing: false,
    issue: None,
    cleanup_issue: None,
    operations: None,
    progress: None,
    producers: [],
    positions: [],
    finished_inputs: [],
    live: Ref(true),
    completed: None,
    finalization_invoked: false,
    execution_settled: false,
  }
  value.tasks[4] = record
  let before = @resources.ledger_usage(root)
  if !pending_case {
    assert_eq(advance_managed_task_lifecycle(nonce + 1L, 4, 1), -2)
    assert_eq(advance_managed_task_lifecycle(nonce, 5, 1), -2)
    assert_eq(advance_managed_task_lifecycle(nonce, 4, 0), -3)
    assert_eq(advance_managed_task_lifecycle(nonce, 4, 1), -2)
    assert_false(record.invoked)
    record.invoked = true
    // Invalid/no-action state still checks the original current. It must not
    // become a metadata-only continuation or success.
    assert_eq(advance_managed_task_lifecycle(nonce, 4, 1), -2)
  } else {
    record.invoked = true
    record.pending = true
    assert_eq(advance_managed_task_lifecycle(nonce, 4, 1), -33)
    assert_true(record.pending)
    record.pending = false
    let original : @local_run.LocalComputeIssue = @local_run.UnsupportedCapability
    record.issue = Some(original)
    assert_eq(advance_managed_task_lifecycle(nonce, 4, 1), -32)
    guard record.issue is Some(retained) else {
      abort("original task cause lost")
    }
    assert_true(physical_equal(retained, original))
    record.closing = true
    assert_eq(advance_managed_task_lifecycle(nonce, 4, 1), -5)
  }
  assert_true(
    record.live.val && record.operations is None && record.completed is None,
  )
  assert_eq(@resources.ledger_usage(root), before)
  value.tasks.remove(4) |> ignore
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
}

///|
test "task drive exported validation reaches the same current before work" {
  task_drive_current_refusal_case(false)
}

///|
test "task drive exported validation reaches pending reentry and original first cause" {
  task_drive_current_refusal_case(true)
}

///|
// Original Core preparation, Run and configured task inventory. Account/start
// facts are explicit component ports, not an ordinary SDK/cancellation receipt.
// The existing release harness refuses every physical Host import.
fn unstarted_cleanup_fixture(
  nonce : Int64,
) -> (
  Instance,
  @buffers.BufferPool,
  @resources.SharedCapacity,
  @buffers.BufferSlot,
  @buffers.BufferSlot,
) raise {
  let (value, preparation, pool, capacity, source_slot, environment_slot) = published_preparation_fixture(
    nonce,
    "SELECT 1 AS n",
    retained_bytes=671088640L,
    execution_bytes=671088640L,
  )
  assert_eq(prepare_program(nonce, 2), 0)
  let submitted = preparation.submitted.unwrap()
  let input = @preparation.local_submitted_preparation_input(submitted)
  let account = @authorization.admit_account_configuration({
    account_id: "unstarted-cleanup",
    entries: [
      {
        entry_id: "same-original",
        outcome: Allow,
        scope: {
          principal: All,
          connection: AnyOf(["python.local"]),
          resource: AnyOf(["runs"]),
          operation: AnyOf(["submit"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  let tuple : @authorization.AccessTuple = {
    principal: "local-user",
    connection: "python.local",
    resource: "runs",
    operation: "submit",
  }
  let context = "sha256:" + "a".repeat(64)
  let authority = "sha256:" + "b".repeat(64)
  let policy = "sha256:" + "c".repeat(64)
  let permit = @authorization.bind_dispatch_authorization(
    account,
    tuple,
    @authorization.Activation,
    @host.prepared_client_identity(@preparation.local_prepared_program(input)).program_definition_cid,
    context,
  ).unwrap()
  let plan = @local_run.prepare_source_free_local_run(
    input,
    authority,
    "unstarted-cleanup",
    permit,
    account,
    tuple,
    context,
    policy,
    "local",
    "unstarted-cleanup",
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
    submitted=Some(submitted),
  ).unwrap()
  let assets = @host.client_local_product_assets()
  let host = @local_run.configure_source_free_local_compute_on_ledger(
    plan,
    value.root,
    value.installed_sequences.contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let start = @local_run.confirm_local_run_physical_start(
    plan,
    @local_run.local_run_request(plan),
    @local_run.local_run_definition_cid(plan),
    true,
    true,
    false,
    false,
    permit,
    account,
    tuple,
    context,
  ).unwrap()
  value.run_configurations[3] = {
    borrow: @buffers.borrow_buffer(pool, environment_slot, () => true).unwrap(),
    account,
    tuple,
    authority_scope_cid: authority,
    context_cid: context,
    policy_cid: policy,
    run_namespace: "local",
    source_free_result_policy: None,
    host_current: None,
    sdk: None,
  }
  value.runs[4] = {
    borrow: @buffers.borrow_buffer(pool, source_slot, () => true).unwrap(),
    slot: source_slot,
    input_physical: 0,
    configuration: 3,
    preparation: 2,
    invoked: true,
    restoration: None,
    physical_start_reserved: true,
    native_source_reserved: false,
    source_free_compute_reserved: true,
    normalization: None,
    outcome: Some(Ok(plan)),
    finite_policy: None,
    sdk_submission: None,
    saved_snapshot: None,
    sdk_row_original: None,
    sdk_row_capacity: None,
  }
  value.physical_starts[5] = {
    run: 4,
    current_configuration: 3,
    borrow: @buffers.borrow_buffer(pool, source_slot, () => true).unwrap(),
    invoked: true,
    outcome: Some(Ok(start)),
    sdk_step: None,
  }
  value.computes[6] = {
    origin: SourceFree(4, 5),
    borrow: @buffers.borrow_buffer(pool, source_slot, () => true).unwrap(),
    current_configuration: Some(3),
    invoked: true,
    pending: false,
    closing: false,
    outcome: Some(Ok(())),
    host: Some(host),
    start: Some(@local_run.bind_local_compute_start(host, start).unwrap()),
    capture: None,
  }
  (value, pool, capacity, source_slot, environment_slot)
}

///|
fn unstarted_cleanup_fixture_close(
  nonce : Int64,
  pool : @buffers.BufferPool,
  capacity : @resources.SharedCapacity,
  source_slot : @buffers.BufferSlot,
  environment_slot : @buffers.BufferSlot,
) -> Unit raise {
  assert_eq(close_native_compute(nonce, 6), 0)
  assert_eq(close_physical_start(nonce, 5), 0)
  assert_eq(close_run(nonce, 4), 0)
  assert_eq(close_run_configuration(nonce, 3), 0)
  published_preparation_close(
    nonce, pool, capacity, source_slot, environment_slot,
  )
}

///|
test "unstarted cleanup cursor retains actual reserved task through current refusal and close" {
  let nonce = 7144L
  let (value, pool, capacity, source_slot, environment_slot) = unstarted_cleanup_fixture(
    nonce,
  )
  let handle = reserve_managed_task(nonce, 6, 3)
  assert_true(handle > 0)
  let original = value.tasks[handle]
  assert_false(original.invoked || original.pending || original.closing)
  assert_true(original.operations is None)
  let current = value.run_configurations[3]
  // The selected original current configuration disappears before activation.
  // Existing start validation must refuse without fabricating a provider.
  value.run_configurations.remove(3) |> ignore
  assert_eq(start_managed_task(nonce, handle), -2)
  value.run_configurations[3] = current
  assert_false(original.invoked)
  assert_true(physical_equal(value.tasks[handle], original))
  let before = @resources.ledger_usage(value.root)
  assert_eq(managed_task_progress(nonce, handle, 5), -1L)
  assert_eq(@resources.ledger_usage(value.root), before)
  assert_true(original.live.val && !original.closing)
  assert_true(physical_equal(value.tasks[handle], original))
  assert_eq(close_managed_task(nonce, handle), 0)
  assert_false(value.tasks.contains(handle))
  assert_false(original.live.val)
  assert_eq(managed_task_progress(nonce, handle, 5), -33L)
  unstarted_cleanup_fixture_close(
    nonce, pool, capacity, source_slot, environment_slot,
  )
}

///|
test "unstarted cleanup cursor keeps missing pending and field four refusals distinct" {
  let nonce = 7145L
  let (value, pool, capacity, source_slot, environment_slot) = unstarted_cleanup_fixture(
    nonce,
  )
  let handle = reserve_managed_task(nonce, 6, 3)
  assert_true(handle > 0)
  let original = value.tasks[handle]
  assert_eq(managed_task_progress(nonce + 1L, handle, 5), -33L)
  assert_eq(managed_task_progress(nonce, handle + 1, 5), -33L)
  assert_eq(managed_task_progress(nonce, handle, 4), -33L)
  original.pending = true
  assert_eq(managed_task_progress(nonce, handle, 5), -33L)
  assert_eq(close_managed_task(nonce, handle), -33)
  assert_true(physical_equal(value.tasks[handle], original))
  original.pending = false
  assert_eq(managed_task_progress(nonce, handle, 5), -1L)
  assert_eq(managed_task_progress(nonce, handle, 4), -33L)
  assert_eq(close_managed_task(nonce, handle), 0)
  assert_false(value.tasks.contains(handle))
  unstarted_cleanup_fixture_close(
    nonce, pool, capacity, source_slot, environment_slot,
  )
}
