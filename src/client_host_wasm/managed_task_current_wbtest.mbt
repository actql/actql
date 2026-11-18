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
