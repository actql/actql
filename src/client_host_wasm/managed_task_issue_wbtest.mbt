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
    cleanup_issue: None,
    operations: None,
    progress: None,
    producer_handles: [],
    input_port: 0,
    input_row: 0,
    live: Ref(true),
    completed: None,
    finalization_invoked: false,
    execution_settled: false,
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

///|
// Lookup-only fixture with real instance/buffer custody. These records grant
// no task activation or completed input; callers still check those originals.
test "managed producer lookup distinguishes source-free task zero from the captured prefix" {
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
  let nonce = 7142L
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
  let slot = @buffers.reserve_output_buffer(pool, 2, 0L, () => true).unwrap()
  @buffers.supply_buffer_output(pool, slot, b"{}").unwrap()
  let borrows = []
  for (handle, origin) in [(11, SourceFree(1, 2)), (12, Captured(3))] {
    let borrow = @buffers.borrow_buffer(pool, slot, () => true).unwrap()
    borrows.push(borrow)
    value.computes[handle] = {
      origin,
      borrow,
      current_configuration: None,
      invoked: false,
      pending: false,
      closing: false,
      outcome: None,
      host: None,
      start: None,
      capture: None,
    }
  }
  let records : Array[StoredManagedTask] = []
  for
    (handle, compute, task) in [
      (21, 11, 0),
      (22, 12, 0),
      (23, 12, 1),
      (24, 13, 0),
    ] {
    let record : StoredManagedTask = {
      compute,
      current_configuration: 2,
      task,
      invoked: false,
      pending: false,
      closing: false,
      issue: None,
      cleanup_issue: None,
      operations: None,
      progress: None,
      producer_handles: [],
      input_port: 0,
      input_row: 0,
      live: Ref(true),
      completed: None,
      finalization_invoked: false,
      execution_settled: false,
    }
    value.tasks[handle] = record
    records.push(record)
  }
  let before = @buffers.buffer_pool_usage(pool)
  let source_free = bind_managed_producer_handle(value, 11, 0)
  let captured = bind_managed_producer_handle(value, 12, 0)
  let positive = bind_managed_producer_handle(value, 12, 1)
  assert_eq(source_free, 21)
  assert_eq(captured, 0)
  assert_eq(positive, 23)
  assert_eq(bind_managed_producer_handle(value, 13, 0), -2)
  assert_eq(bind_managed_producer_handle(value, 11, -1), -2)
  assert_true(bound_managed_producer(value, 11, 23) is None)
  assert_true(bound_managed_producer(value, 12, captured) is None)
  assert_true(
    bound_managed_producer(value, 11, source_free)
    .map(record => physical_equal(record, records[0]))
    .unwrap_or(false),
  )
  assert_true(
    bound_managed_producer(value, 12, positive)
    .map(record => physical_equal(record, records[2]))
    .unwrap_or(false),
  )
  // A later registration cannot stand in for a missing bound original.
  value.tasks.remove(source_free) |> ignore
  value.tasks[25] = { ..records[0], live: Ref(true), }
  assert_eq(bind_managed_producer_handle(value, 11, 0), 25)
  assert_true(bound_managed_producer(value, 11, source_free) is None)
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, before.allocated)
  assert_eq(@buffers.buffer_pool_usage(pool).capacity, before.capacity)
  assert_eq(@buffers.buffer_pool_usage(pool).closing, before.closing)
  assert_true(
    records.all(record => {
      !record.invoked && record.live.val && record.completed is None
    }),
  )
  for handle in [22, 23, 24, 25] {
    value.tasks.remove(handle) |> ignore
  }
  for handle in [11, 12] {
    value.computes.remove(handle) |> ignore
  }
  for borrow in borrows {
    @buffers.return_buffer_borrow(pool, borrow).unwrap()
  }
  @buffers.close_buffer(pool, slot).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
}

///|
// Explicit stored-state fixture, not an historical close arm or normal Run.
// The real private ABI getters must not drive an operation or replace causes.
test "post-close task diagnostic keeps original causes and pending snapshot distinct" {
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
  let nonce = 7146L
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
  let original_issue : @local_run.LocalComputeIssue = @local_run.UnsupportedCapability
  let record : StoredManagedTask = {
    compute: 1,
    current_configuration: 2,
    task: 3,
    invoked: false,
    pending: false,
    closing: false,
    issue: Some(original_issue),
    cleanup_issue: None,
    operations: None,
    progress: None,
    producer_handles: [],
    input_port: 0,
    input_row: 0,
    live: Ref(true),
    completed: None,
    finalization_invoked: false,
    execution_settled: false,
  }
  value.tasks[4] = record
  let before = @resources.ledger_usage(root)
  for field in [6, 7] {
    assert_eq(managed_task_progress(nonce + 1L, 4, field), -33L)
    assert_eq(managed_task_progress(nonce, 5, field), -33L)
    assert_eq(managed_task_progress(nonce, 4, field), 0L)
  }
  record.closing = true
  assert_eq(managed_task_progress(nonce, 4, 6), 3L)
  value.tasks[5] = { ..record, task: 4, producer_handles: [4], }
  assert_eq(managed_task_progress(nonce, 4, 6), 2L)
  assert_eq(close_managed_task(nonce, 4), -9)
  assert_true(record.live.val)
  value.tasks.remove(5) |> ignore
  for
    (cause, expected) in [
      (@managed.ControlWorkLimit(17), 82L),
      (@managed.LogicalWorkLimit(17, 3L, @managed.Unspecified), 71L),
      (
        @managed.ExecutionCapacityRefusal(
          @resources.RetentionLimit,
          19L,
          7L,
          512L,
        ),
        83L,
      ),
    ] {
    record.cleanup_issue = Some(cause)
    assert_eq(managed_task_issue(nonce, 4), 2)
    assert_eq(managed_task_progress(nonce, 4, 7), expected)
    assert_eq(managed_task_progress(nonce, 4, 6), 3L)
    guard record.cleanup_issue is Some(retained) else {
      abort("original cleanup cause disappeared")
    }
    assert_true(physical_equal(retained, cause))
    guard record.issue is Some(retained_issue) else {
      abort("original execution cause disappeared")
    }
    assert_true(physical_equal(retained_issue, original_issue))
  }
  record.pending = true
  assert_eq(managed_task_progress(nonce, 4, 6), -33L)
  assert_eq(managed_task_progress(nonce, 4, 7), -33L)
  record.pending = false
  assert_eq(managed_task_progress(nonce, 4, 4), -33L)
  assert_eq(managed_task_progress(nonce, 4, 5), -1L)
  assert_true(record.live.val && !record.invoked && record.operations is None)
  assert_true(physical_equal(value.tasks[4], record))
  assert_eq(@resources.ledger_usage(root), before)
  assert_eq(close_managed_task(nonce, 4), 0)
  assert_eq(managed_task_progress(nonce, 4, 6), -33L)
  assert_eq(managed_task_progress(nonce, 4, 7), -33L)
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
}
