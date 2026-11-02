///|
fn interrupted_saved_export(
  publication : Int,
  slot : @buffers.BufferSlot,
) -> StoredPublicationCommitExport {
  {
    publication,
    slot,
    projection: None,
    invoked: true,
    pending: true,
    produced: false,
    closing: false,
    output_closed: false,
    state_borrow: None,
    sdk_delivery_first: None,
    sdk_payload_outcome: None,
    sdk_payload_tick_borrow: None,
    sdk_payload_clock_input: None,
    sdk_payload_invoked: true,
    sdk_payload_parent: None,
    sdk_payload_confirmed: None,
    sdk_payload_record: None,
    sdk_payload_terminal: None,
    sdk_run_state_update: None,
  }
}

///|
test "saved interruption cleanup spends normal entry but retains original loans and cleanup refusal" {
  let root = @resources.create_ledger({
    planning_work: 100000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 33554432L,
    retained_bytes: 33554432L,
    execution_bytes: 33554432L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 8388608L, 16, 1048576).unwrap()
  assert_eq(
    install_buffer_instance(
      1901L,
      root,
      capacity,
      None,
      pool,
      16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(1901L).unwrap()
  let parent_slot = @buffers.reserve_output_buffer(pool, 64, 64L, () => true).unwrap()
  let parent : StoredSubmissionProjection = {
    configuration: 1,
    kind: 6,
    borrow: Err(CleanupPending),
    slot: parent_slot,
    saved_result: None,
    saved_snapshot: None,
    append_plan: None,
    failure_preparation: None,
    failure_plan: None,
    invoked: true,
    produced: false,
    output_closed: false,
  }
  value.submissions[10] = parent
  let ready = Ref(false)
  let slot = @buffers.reserve_output_buffer(pool, 64, 64L, () => ready.val).unwrap()
  @buffers.supply_buffer_output(pool, slot, b"{}").unwrap()
  let held = @buffers.borrow_buffer(pool, slot, () => true).unwrap()
  let child = interrupted_saved_export(10, slot)
  value.commit_exports[20] = child
  value.copies[20] = (slot, 30)
  let foreign = interrupted_saved_export(11, slot)
  value.commit_exports[21] = foreign
  let before = @buffers.buffer_pool_usage(pool)
  assert_eq(begin_submission_cleanup(1902L, 10), -2)
  assert_eq(begin_submission_cleanup(1901L, 11), -2)
  assert_true(!value.closing)
  assert_true(child.pending)
  assert_eq(close_publication_commit_export(1901L, 20), -33)
  assert_true(value.commit_exports.contains(20))
  assert_eq(begin_submission_cleanup(1901L, 10), 0)
  assert_true(value.closing)
  assert_true(child.closing && !child.pending)
  assert_true(child.invoked && child.sdk_payload_invoked)
  assert_true(foreign.pending && !foreign.closing)
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, before.allocated)
  assert_eq(@buffers.buffer_pool_usage(pool).capacity, before.capacity)
  assert_eq(@buffers.buffer_pool_usage(pool).closing, before.closing)
  // This asserts the real shared admission boundary, not a physical Host call.
  // The exported wrapper must return this refusal before installing cleanup.
  assert_eq(reserve_input_admission(value, 40), -5)
  assert_eq(close_publication_commit_export(1901L, 20), -9)
  @buffers.return_buffer_borrow(pool, held).unwrap()
  assert_eq(close_publication_commit_export(1901L, 20), -9)
  assert_true(value.commit_exports.contains(20))
  ready.val = true
  assert_eq(close_publication_commit_export(1901L, 20), 0)
  assert_true(!value.commit_exports.contains(20))
  assert_true(value.submissions.contains(10))
  assert_true(value.commit_exports.contains(21))
  // The test's artificial foreign metadata shares no independent allocation.
  value.commit_exports.remove(21) |> ignore
  value.submissions.remove(10) |> ignore
  @buffers.close_buffer(pool, parent_slot).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  instance.val = None
}
