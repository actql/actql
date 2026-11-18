///|
// Pure row validation and existing Ledger/Run cleanup only. No physical Store,
// current or dispatch authority is created by this component fixture.
fn sdk_row_original_fixture(
  retention : Int64,
) -> (Instance, StoredRun, @buffers.BufferSlot) raise {
  let root = @resources.create_ledger({
    planning_work: 100000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 33554432L,
    retained_bytes: retention,
    execution_bytes: 268435456L,
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
        old="\"cancellation_requested\":false",
        new="\"cancellation_requested\":true",
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
  assert_true(fresh.cancellation_requested)
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
