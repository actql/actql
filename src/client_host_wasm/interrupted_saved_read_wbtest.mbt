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
    sdk_delivery_prepared: None,
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
    sdk_run_state_update_capacity: None,
    sdk_transport_capacity: None,
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
    append_plan: Idle,
    append_reader_serial: 0L,
    failure_preparation: None,
    failure_plan: None,
    cancellation_append: None,
    unpublished_state: None,
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

///|
test "live delivery interruption only retires the original preparation latches" {
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
      1903L,
      root,
      capacity,
      None,
      pool,
      16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(1903L).unwrap()
  let first_slot = @buffers.reserve_output_buffer(pool, 1, 64L, () => true).unwrap()
  let first = interrupted_saved_export(10, first_slot)
  first.projection = Some(SDKReadDeliveryStorage(1, 2))
  value.commit_exports[20] = first
  let ready = Ref(false)
  let body_slot = @buffers.reserve_output_buffer(pool, 512, 512L, () => {
    ready.val
  }).unwrap()
  let body = interrupted_saved_export(10, body_slot)
  body.projection = Some(SDKReadDeliveryBody(20))
  body.sdk_payload_parent = Some(20)
  value.commit_exports[21] = body
  let foreign = interrupted_saved_export(10, body_slot)
  foreign.projection = Some(SDKReadDeliveryBody(22))
  foreign.sdk_payload_parent = Some(22)
  value.commit_exports[23] = foreign
  let later = interrupted_saved_export(10, first_slot)
  later.projection = Some(SDKReadDeliveryStorage(3, 4))
  later.produced = true
  value.commit_exports[24] = later

  assert_eq(retire_interrupted_sdk_delivery_preparation(value, 11, 20), -2)
  assert_eq(retire_interrupted_sdk_delivery_preparation(value, 10, 21), -2)
  assert_eq(retire_interrupted_sdk_delivery_preparation(value, 10, 24), -33)
  assert_true(first.pending && body.pending && !value.closing)
  let retained = @buffers.buffer_pool_usage(pool).allocated
  assert_eq(retire_interrupted_sdk_delivery_preparation(value, 10, 20), 0)
  assert_true(value.closing && first.closing && body.closing)
  assert_false(first.pending)
  assert_false(body.pending)
  assert_true(foreign.pending && !foreign.closing)
  assert_true(later.pending && !later.closing)
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, retained)
  assert_eq(close_publication_commit_export(1903L, 20), -33)
  assert_eq(close_publication_commit_export(1903L, 21), -9)
  assert_true(
    value.commit_exports.contains(20) && value.commit_exports.contains(21),
  )
  ready.val = true
  assert_eq(close_publication_commit_export(1903L, 21), 0)
  assert_eq(close_publication_commit_export(1903L, 20), 0)
  // Foreign test metadata did not allocate extra slots.
  value.commit_exports.remove(23) |> ignore
  value.commit_exports.remove(24) |> ignore
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  instance.val = None
}

///|
test "File prepublication unwind retires only the selected synchronous Read and Result latches" {
  let nonce = 1904L
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
      nonce, root, capacity, None, pool, 16, prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(nonce).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"terminal-control","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json, local_check_test_environment(), None, @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let request = @host.prepare_source_free_client_request_identity(
    prepared, "sha256:" + "a".repeat(64), "terminal-control",
  ).unwrap()
  let work_capacity = @resources.reserve_capacity(root, 4096L, 4096L).unwrap()
  let read_capacity = @resources.reserve_capacity(root, 2048L, 2048L).unwrap()
  let work : StoredSDKFileCaptureWork = {
    source: 8, prepared, request, capacity: work_capacity,
    host: None, tasks: None, task_capacity: None, result: None,
    invocation: None, invocation_capacity: None, invocation_ready: true,
    results_ready: true, stepping: false, failed: false, closing: false,
  }
  // The fixture fixes the already-selected nominal owners; it does not
  // simulate a physical File source, Wasm trap or transaction acknowledgement.
  let file : StoredFilePublicationPreflight = {
    start: 7, work, prepared: None, capacity: None, request_started: false,
    request_failure: None, request_publisher: None, capture_started: false,
  }
  let foreign_file : StoredFilePublicationPreflight = {
    start: file.start, work, prepared: None, capacity: None, request_started: false,
    request_failure: None, request_publisher: None, capture_started: false,
  }
  let ready = Ref(false)
  let slot = @buffers.reserve_output_buffer(pool, 64, 64L, () => ready.val).unwrap()
  let chunk_slot = @buffers.reserve_output_buffer(pool, 64, 64L, () => true).unwrap()
  @buffers.supply_buffer_output(pool, chunk_slot, b"[]").unwrap()
  let parent : StoredPublicationPreflight = {
    origin: FilePublicationPreflight(file), borrow: Err(CleanupPending),
    slot, invoked: true, pending: true, closing: false, produced: false,
    output_closed: false,
  }
  let handle = 10
  value.publication_preflights[handle] = parent
  let publication_handle = 41
  let returned = Ref(false)
  let publication_slot = @buffers.reserve_output_buffer(
    pool, 0, 64L, () => returned.val,
  ).unwrap()
  let publication = stored_publication_output(
    file.start, handle,
    Some({
      original: file, results: [], manifest: None, capacity: None,
      retained: 0L, execution: 0L, state_export: None,
    }),
    Err(CleanupPending), publication_slot,
  )
  value.publications[publication_handle] = publication
  value.copies[publication_handle] = (publication_slot, 51)

  // File holds the original cleanup without allocating an outward wire.
  // Supplying the empty output does not itself latch semantic completion.
  @buffers.supply_buffer_output(pool, publication_slot, b"").unwrap()
  assert_eq(publication_length(nonce, publication_handle), -33)
  assert_eq(read_packed(nonce, publication_handle, 0, 2), -33L)
  assert_eq(borrow(nonce, publication_handle), -33)
  publication.produced = true
  publication.pending = true
  assert_eq(publication_length(nonce, publication_handle), -33)
  assert_eq(read_block(nonce, publication_handle, 0, 2), -33)
  publication.pending = false
  publication.failed = true
  assert_eq(publication_length(nonce, publication_handle), -33)
  assert_eq(byte(nonce, publication_handle, 0), -33)
  publication.failed = false
  assert_eq(publication_length(nonce, publication_handle), 0)
  assert_eq(byte(nonce, publication_handle, 0), -5)
  publication.output_closed = true
  assert_eq(publication_length(nonce, publication_handle), -5)
  assert_eq(read_packed(nonce, publication_handle, 0, 2), -5L)
  publication.output_closed = false
  assert_eq(close_publication(nonce, publication_handle), -9)
  assert_true(value.publications.contains(publication_handle))
  assert_eq(publication_length(nonce, publication_handle), -5)
  assert_eq(read_packed(nonce, publication_handle, 0, 2), -5L)
  returned.val = true
  assert_eq(close_publication(nonce, publication_handle), 0)
  assert_false(value.publications.contains(publication_handle))

  let claim : StoredSDKFileStart = {
    publication_material: 9, dispatch_material: None, capacity: Some(read_capacity),
    step: None, observed: None, reading: Some(FileStartMaterialRead),
  }
  let captured_export = reserve_result_export_record(value, 0, FileNamedResult({
    parent: handle, start: 7, work, preparation: None, capacity: None,
    retained: 0L, initial_execution: 0L, execution: 0L, quote_failure: None,
    retiring: false,
  }))
  let result = value.result_exports.get(captured_export).unwrap()
  result.pending = true
  let retiring_export = reserve_result_export_record(value, 1, FileNamedResult({
    parent: handle, start: 7, work, preparation: None, capacity: None,
    retained: 0L, initial_execution: 0L, execution: 0L, quote_failure: None,
    retiring: true,
  }))
  let retiring = value.result_exports.get(retiring_export).unwrap()
  retiring.pending = true
  let unrelated_export = reserve_result_export_record(value, 0, TaskResult(300))
  let unrelated = value.result_exports.get(unrelated_export).unwrap()
  unrelated.pending = true
  let chunk_handle = 42
  let chunk : StoredResultChunk = {
    result: captured_export, physical_ticket: 52, slot: Some(chunk_slot), reservation_issue: 0,
    invoked: true, pending: true, produced: true, final_chunk: false, closing: false,
  }
  value.result_chunks[chunk_handle] = chunk
  value.copies[chunk_handle] = (chunk_slot, chunk.physical_ticket)

  // Bytes already in the original output slot still need the File result's
  // completed step. Both the typed getter and generic transport agree.
  result.pending = false
  chunk.pending = false
  chunk.produced = false
  assert_eq(read_packed(nonce, chunk_handle, 0, 2), -33L)
  chunk.produced = true
  assert_eq(result_chunk_length(nonce, chunk_handle), 2)
  assert_eq(read_packed(nonce, chunk_handle, 0, 2), 0x5d5bL)
  result.pending = true
  chunk.pending = true

  assert_eq(begin_file_prepublication_cleanup_after_unwind(nonce, handle), -2)
  assert_eq(seal_interrupted_file_prepublication(value, handle, parent, file, claim), -9)
  claim.reading = Some(FileStartPreflightRead(foreign_file))
  assert_eq(seal_interrupted_file_prepublication(value, handle, parent, file, claim), -35)
  assert_true(parent.pending && !parent.closing && !work.closing)
  assert_true(result.pending && chunk.pending && !result.closing)
  assert_eq(result_chunk_length(nonce, chunk_handle), -33)
  assert_eq(result_chunk_final(nonce, chunk_handle), -33)
  assert_eq(read_block(nonce, chunk_handle, 0, 2), -33)
  assert_eq(byte(nonce, chunk_handle, 0), -33)
  assert_eq(read_packed(nonce, chunk_handle, 0, 2), -33L)
  assert_eq(borrow(nonce, chunk_handle), -33)
  claim.reading = Some(FileStartPreflightRead(file))
  let allocated = @buffers.buffer_pool_usage(pool).allocated
  let debt = @resources.ledger_usage(root)
  assert_eq(seal_interrupted_file_prepublication(value, handle, parent, file, claim), 0)
  assert_true(parent.closing && !parent.pending && work.closing)
  assert_true(claim.reading is None)
  assert_true(result.closing && !result.pending && chunk.closing && !chunk.pending)
  assert_true(retiring.pending && retiring.closing)
  assert_true(unrelated.pending && !unrelated.closing)
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, allocated)
  assert_eq(@resources.ledger_usage(root), debt)
  assert_eq(result_chunk_length(nonce, chunk_handle), -5)
  assert_eq(result_chunk_final(nonce, chunk_handle), -5)
  assert_eq(read_packed(nonce, chunk_handle, 0, 2), -5L)
  assert_eq(borrow(nonce, chunk_handle), -5)
  assert_eq(close_result_export(nonce, retiring_export), -9)

  // Retiring the test's original loan still needs its actual buffer callback;
  // the terminal transition did not supply it.
  assert_true(@buffers.close_buffer(pool, slot) is Err(CleanupPending))
  ready.val = true
  @buffers.close_buffer(pool, slot).unwrap()
  @buffers.close_buffer(pool, chunk_slot).unwrap()
  value.copies.remove(chunk_handle) |> ignore
  value.result_chunks.remove(chunk_handle) |> ignore
  value.result_exports.remove(captured_export) |> ignore
  value.result_exports.remove(retiring_export) |> ignore
  value.result_exports.remove(unrelated_export) |> ignore
  value.publication_preflights.remove(handle) |> ignore
  @resources.settle_capacity(root, read_capacity).unwrap()
  @resources.settle_capacity(root, work_capacity).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  instance.val = None
}
