///|
// Explicit instance/ledger fixture only. The projection must leave the original
// typed failure in the task; it performs no Run start or physical operation.
test "managed task issue projects memory refusal without replacing its original payload" {
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
  let nonce = 7141L
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
    task: 3,
    invoked: true,
    pending: false,
    closing: false,
    issue: None,
    operations: None,
    progress: None,
    producers: [],
    positions: [],
    finished_inputs: [],
    live: Ref(true),
    completed: None,
    finalization_invoked: false,
  }
  value.tasks[4] = record
  assert_eq(managed_task_issue(nonce + 1L, 4), -2)
  assert_eq(managed_task_issue(nonce, 5), -2)
  assert_eq(managed_task_issue(nonce, 4), -33)
  for
    (cause, dimension) in [
      (@resources.RetentionLimit, "retained_bytes"),
      (@resources.ExecutionLimit, "execution_bytes"),
    ] {
    let original = @managed.ExecutionCapacityRefusal(cause, 19L, 7L, 512L)
    record.issue = Some(@local_run.Managed(original))
    assert_eq(managed_task_issue(nonce, 4), 83)
    assert_eq(managed_task_issue(nonce, 4), 83)
    guard record.issue is Some(@local_run.Managed(retained)) else {
      abort("original managed failure disappeared")
    }
    assert_true(physical_equal(retained, original))
    assert_eq(
      @managed.local_managed_failure_budget(retained),
      Some((dimension, true, 19L, 7L, 512L)),
    )
    assert_true(record.live.val)
    assert_false(record.pending)
    assert_false(record.closing)
  }
  record.issue = Some(@local_run.Managed(@managed.ControlWorkLimit(123)))
  assert_eq(managed_task_issue(nonce, 4), 82)
  value.tasks.remove(4) |> ignore
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
}
