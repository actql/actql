///|
// Pure row validation and existing Ledger/Run cleanup only. No physical Store,
// current or dispatch authority is created by this component fixture.
fn sdk_row_original_fixture(
  retention : Int64,
  execution? : Int64 = 268435456L,
) -> (Instance, StoredRun, @buffers.BufferSlot) raise {
  let root = @resources.create_ledger({
    planning_work: 100000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 33554432L,
    retained_bytes: retention,
    execution_bytes: execution,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 4096L, 16, 1048576).unwrap()
  assert_eq(
    install_buffer_instance(
      7197L,
      root,
      capacity,
      None,
      pool,
      16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(7197L).unwrap()
  let slot = @buffers.reserve_buffer(pool, 2, 0L, () => true).unwrap()
  @buffers.fill_buffer(pool, slot, 0, 2, i => Some(b"{}"[i])).unwrap()
  @buffers.seal_buffer(pool, slot, 2, 1).unwrap()
  let record : StoredRun = {
    borrow: @buffers.borrow_buffer(pool, slot, () => true).unwrap(),
    slot,
    input_physical: 0,
    configuration: 0,
    preparation: 0,
    invoked: false,
    restoration: None,
    physical_start_reserved: false,
    native_source_reserved: false,
    source_free_compute_reserved: false,
    normalization: None,
    outcome: None,
    finite_policy: None,
    sdk_submission: None,
    saved_snapshot: None,
    sdk_row_original: None,
    sdk_row_capacity: None,
  }
  value.runs[1] = record
  (value, record, slot)
}

///|
fn sdk_row_original_fixture_close(
  value : Instance,
  slot : @buffers.BufferSlot,
) -> Unit raise {
  assert_eq(close_run(value.nonce, 1), 0)
  @buffers.close_buffer(value.pool, slot).unwrap()
  @buffers.close_pool(value.pool).unwrap()
  @resources.close_shared_capacity(value.wasm_capacity).unwrap()
  @resources.settle_shared_capacity(value.wasm_capacity).unwrap()
  instance.val = None
}

///|
test "SDK row exact result reuse retains charged original until same Run cleanup" {
  let (value, record, slot) = sdk_row_original_fixture(33554432L)
  let body = @utf8.encode(submission_identity_wire)
  let original = submission_append_run_inspection(submission_identity_row(body)).unwrap()
  let row : @host.ClientJournalPhysicalRow = {
    key: @host.client_request_scope_cid(original.request),
    revision: 7L,
    body,
  }
  let before = @resources.ledger_usage(value.root)
  let first = sdk_run_row_original_with_identity(
    value,
    record,
    original.request,
    original.definition,
    row,
  ).unwrap()
  let token = record.sdk_row_capacity.unwrap()
  let charged = @resources.ledger_usage(value.root)
  assert_true(
    charged.reserved_retention_bytes > before.reserved_retention_bytes,
  )
  let second = sdk_run_row_original_with_identity(
    value,
    record,
    original.request,
    original.definition,
    row,
  ).unwrap()
  assert_true(physical_equal(first, second))
  assert_true(physical_equal(record.sdk_row_capacity.unwrap(), token))
  assert_eq(@resources.ledger_usage(value.root), charged)
  // The typed row remains DATA; a missing original Plan still refuses the
  // real caller before it can use this private pure validator result.
  assert_true(sdk_run_row_original(value, 1, row) is Err(-2))
  let cancelled = {
    ..row,
    revision: 8L,
    body: @utf8.encode(
      submission_identity_wire.replace(
        old="\"cancellation_head\":null",
        new="\"cancellation_head\":{\"observed_revision\":\"8\",\"record_key\":\"3ec097f4b1602404e88a04cfe7da4c13504e50a5358aae9e3841039c77f6ebcd\"}",
      ),
    ),
  }
  let fresh = sdk_run_row_original_with_identity(
    value,
    record,
    original.request,
    original.definition,
    cancelled,
  ).unwrap()
  assert_true(fresh.cancellation_requested())
  assert_false(physical_equal(first, fresh))
  assert_false(physical_equal(record.sdk_row_capacity.unwrap(), token))
  let malformed = { ..row, body: b"{}", }
  assert_true(
    sdk_run_row_original_with_identity(
      value,
      record,
      original.request,
      original.definition,
      malformed,
    )
    is Err(-31),
  )
  assert_true(record.sdk_row_original is None)
  assert_true(record.sdk_row_capacity is Some(_))
  sdk_row_original_fixture_close(value, slot)
  assert_eq(@resources.ledger_usage(value.root).reserved_retention_bytes, 0L)
}

///|
test "SDK row retention refuses before construction and foreign row never seeds original" {
  let (value, record, slot) = sdk_row_original_fixture(65536L)
  let body = @utf8.encode(submission_identity_wire)
  let original = submission_append_run_inspection(submission_identity_row(body)).unwrap()
  let row : @host.ClientJournalPhysicalRow = {
    key: @host.client_request_scope_cid(original.request),
    revision: 7L,
    body,
  }
  let before = @resources.ledger_usage(value.root)
  assert_true(
    sdk_run_row_original_with_identity(
      value,
      record,
      original.request,
      original.definition,
      row,
    )
    is Err(-4),
  )
  assert_true(
    record.sdk_row_original is None && record.sdk_row_capacity is None,
  )
  assert_eq(@resources.ledger_usage(value.root), before)
  let foreign = { ..row, key: "foreign-original", }
  ignore(
    sdk_run_row_original_with_identity(
      value,
      record,
      original.request,
      original.definition,
      foreign,
    ).unwrap(),
  )
  assert_true(
    record.sdk_row_original is None && record.sdk_row_capacity is None,
  )
  assert_true(sdk_row_original_capacity(0) is None)
  assert_true(sdk_row_original_capacity(131073) is None)
  sdk_row_original_fixture_close(value, slot)
}

///|
test "SDK RunState candidate keeps its original Run and Ledger through close refusal" {
  let (value, _, source) = sdk_row_original_fixture(33554432L)
  let unblocked = Ref(false)
  let slot = @buffers.reserve_output_buffer(value.pool, 1, 0L, () => {
    unblocked.val
  }).unwrap()
  let before = @resources.ledger_usage(value.root)
  let (retained, execution) = sdk_run_state_update_construction_capacity().unwrap()
  let capacity = @resources.reserve_capacity(value.root, retained, execution).unwrap()
  let projection = interrupted_saved_export(10, slot)
  projection.projection = Some(SDKMeasuredRunState(0, 1, 100, false))
  projection.pending = false
  projection.sdk_run_state_update_capacity = Some(capacity)
  value.commit_exports[20] = projection
  let charged = @resources.ledger_usage(value.root)
  assert_eq(
    charged.reserved_retention_bytes - before.reserved_retention_bytes,
    retained,
  )
  assert_eq(
    charged.reserved_execution_bytes - before.reserved_execution_bytes,
    execution,
  )
  assert_eq(close_run(value.nonce, 1), -9)
  assert_eq(close_publication_commit_export(value.nonce, 20), -9)
  assert_true(
    physical_equal(projection.sdk_run_state_update_capacity.unwrap(), capacity),
  )
  assert_eq(@resources.ledger_usage(value.root), charged)
  unblocked.val = true
  assert_eq(close_publication_commit_export(value.nonce, 20), 0)
  let closed = @resources.ledger_usage(value.root)
  assert_eq(closed.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(closed.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(closed.live_reservations, before.live_reservations)
  assert_eq(closed.peak_retention_bytes, charged.peak_retention_bytes)
  sdk_row_original_fixture_close(value, source)
}

///|
test "publisher retains original port until both exact cleanup acknowledgements" {
  let (value, _, input) = sdk_row_original_fixture(33554432L)
  let handle = 73
  let output_closed = Ref(false)
  let input_returned = Ref(false)
  let output = @buffers.reserve_output_buffer(value.pool, 1, 0L, () => {
    output_closed.val
  }).unwrap()
  let input_borrow = @buffers.borrow_buffer(value.pool, input, () => {
    input_returned.val
  }).unwrap()
  let child : StoredPublisher = {
    parent: 0,
    physical: 91,
    slot: output,
    borrow: Ok(input_borrow),
    configuration: 0,
    store: "",
    port: None,
    closing: false,
    unknown: false,
  }
  let cid = "sha256:" + "a".repeat(64)
  let date = "2026-11-27T00:00:00.000Z"
  let request = @publication.seal_publication_contract(
    "publication_request",
    "{\"version\":\"actql-publication-request/0.1\",\"namespace_id\":\"local\",\"authority_scope_cid\":\"\{cid}\",\"run_definition_cid\":\"\{cid}\",\"inventory\":[{\"result_name\":\"answer\",\"result_definition_cid\":\"\{cid}\"}],\"publication_policy_cid\":\"\{cid}\",\"publication_target_cid\":\"\{cid}\",\"requested_at\":\"\{date}\"}",
    4096,
    32,
    4,
  ).unwrap()
  let request_cid = @publication.publication_contract_identity(request)
  let attempt = @publication.seal_publication_contract(
    "publication_attempt",
    "{\"version\":\"actql-publication-attempt/0.1\",\"publication_request_cid\":\"\{request_cid}\",\"run_definition_cid\":\"\{cid}\",\"attempt_id\":\"attempt\",\"fence_cid\":\"\{cid}\",\"started_at\":\"\{date}\"}",
    4096,
    32,
    4,
  ).unwrap()
  let port = @publication.install_publication_publisher_port(
    request,
    attempt,
    cid,
    () => !child.closing,
    _ => !child.closing,
  ).unwrap()
  child.port = Some(port)
  value.publishers[handle] = child
  value.copies[handle] = (output, child.physical)
  assert_eq(close_publisher(value.nonce, handle + 1), -2)
  assert_eq(close_publisher(value.nonce, handle), -9)
  assert_true(physical_equal(value.publishers.get(handle).unwrap(), child))
  assert_true(physical_equal(child.port.unwrap(), port))
  assert_true(value.copies.get(handle) is Some(_))
  output_closed.val = true
  assert_eq(close_publisher(value.nonce, handle), -9)
  assert_true(physical_equal(child.port.unwrap(), port))
  assert_true(value.copies.get(handle) is Some(_))
  input_returned.val = true
  assert_eq(close_publisher(value.nonce, handle), 0)
  assert_true(child.port is None)
  assert_true(value.publishers.get(handle) is None)
  assert_true(value.copies.get(handle) is None)
  assert_eq(close_publisher(value.nonce, handle), -2)
  sdk_row_original_fixture_close(value, input)
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
  let document =
    #|{"version":"actql/0.1","id":"terminal-control","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    local_check_test_environment(),
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let request = @host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "terminal-control",
  ).unwrap()
  let work_capacity = @resources.reserve_capacity(root, 4096L, 4096L).unwrap()
  let read_capacity = @resources.reserve_capacity(root, 2048L, 2048L).unwrap()
  let work : StoredSDKFileCaptureWork = {
    source: 8,
    prepared,
    request,
    capacity: work_capacity,
    host: None,
    tasks: None,
    task_capacity: None,
    result: None,
    invocation: None,
    invocation_capacity: None,
    invocation_ready: true,
    results_ready: true,
    stepping: false,
    failed: false,
    closing: false,
  }
  // The fixture fixes the already-selected nominal owners; it does not
  // simulate a physical File source, Wasm trap or transaction acknowledgement.
  let file : StoredFilePublicationPreflight = {
    start: 7,
    work,
    prepared: None,
    capacity: None,
    request_started: false,
    request_failure: None,
    request_publisher: None,
    capture_started: false,
  }
  let foreign_file : StoredFilePublicationPreflight = {
    start: file.start,
    work,
    prepared: None,
    capacity: None,
    request_started: false,
    request_failure: None,
    request_publisher: None,
    capture_started: false,
  }
  let ready = Ref(false)
  let slot = @buffers.reserve_output_buffer(pool, 64, 64L, () => ready.val).unwrap()
  let chunk_slot = @buffers.reserve_output_buffer(pool, 64, 64L, () => true).unwrap()
  @buffers.supply_buffer_output(pool, chunk_slot, b"[]").unwrap()
  let parent : StoredPublicationPreflight = {
    origin: FilePublicationPreflight(file),
    borrow: Err(CleanupPending),
    slot,
    invoked: true,
    pending: true,
    closing: false,
    produced: false,
    output_closed: false,
  }
  let handle = 10
  value.publication_preflights[handle] = parent
  let publication_handle = 41
  let returned = Ref(false)
  let publication_slot = @buffers.reserve_output_buffer(pool, 0, 64L, () => {
    returned.val
  }).unwrap()
  let publication = stored_publication_output(
    file.start,
    handle,
    Some({
      original: file,
      results: [],
      manifest: None,
      capacity: None,
      retained: 0L,
      execution: 0L,
      state_export: None,
    }),
    Err(CleanupPending),
    publication_slot,
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
    publication_material: 9,
    dispatch_material: None,
    capacity: Some(read_capacity),
    step: None,
    observed: None,
    reading: Some(FileStartMaterialRead),
  }
  let captured_export = reserve_result_export_record(
    value,
    0,
    FileNamedResult({
      parent: handle,
      start: 7,
      work,
      preparation: None,
      capacity: None,
      retained: 0L,
      initial_execution: 0L,
      execution: 0L,
      quote_failure: None,
      retiring: false,
    }),
  )
  let result = value.result_exports.get(captured_export).unwrap()
  result.pending = true
  let retiring_export = reserve_result_export_record(
    value,
    1,
    FileNamedResult({
      parent: handle,
      start: 7,
      work,
      preparation: None,
      capacity: None,
      retained: 0L,
      initial_execution: 0L,
      execution: 0L,
      quote_failure: None,
      retiring: true,
    }),
  )
  let retiring = value.result_exports.get(retiring_export).unwrap()
  retiring.pending = true
  let unrelated_export = reserve_result_export_record(value, 0, TaskResult(300))
  let unrelated = value.result_exports.get(unrelated_export).unwrap()
  unrelated.pending = true
  let chunk_handle = 42
  let chunk : StoredResultChunk = {
    result: captured_export,
    physical_ticket: 52,
    slot: Some(chunk_slot),
    reservation_issue: 0,
    invoked: true,
    pending: true,
    produced: true,
    final_chunk: false,
    closing: false,
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
  assert_eq(
    seal_interrupted_file_prepublication(value, handle, parent, file, claim),
    -9,
  )
  claim.reading = Some(FileStartPreflightRead(foreign_file))
  assert_eq(
    seal_interrupted_file_prepublication(value, handle, parent, file, claim),
    -35,
  )
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
  assert_eq(
    seal_interrupted_file_prepublication(value, handle, parent, file, claim),
    0,
  )
  assert_true(parent.closing && !parent.pending && work.closing)
  assert_true(claim.reading is None)
  assert_true(
    result.closing && !result.pending && chunk.closing && !chunk.pending,
  )
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
