///|
// Real original file/Journal component, with explicit fixture declarations,
// Account/current ports and Arena backing. Not the normal installed caller,
// full constructor geometry or README/Result/Saved/cleanup acceptance.
let file_receipt_original_version = "sha256:7ffebacc55e69ab6c975ab6c3808f478035ef93db564a0f66a80c2e643496773"

///|
test "export original Native file receipt Checkpoint signing references" {
  let (_, _, _, definition) = journal_test_run(
    "checkpoint-request", "checkpoint-run",
  )
  println(
    "ACTQL_CLIENT_CHECKPOINT " +
    receipt_test_checkpoint(definition, file=true).wire,
  )
}

///|
#borrow(path)
extern "C" fn file_receipt_fixture_open(path : Bytes, flags : Int) -> Int = "open"

///|
extern "C" fn file_receipt_fixture_close(fd : Int) -> Int = "close"

///|
fn file_receipt_fixture_work(directory : String) -> Unit raise {
  let declaration = @rows.generate_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "string", nullable: false, },
          { name: "value", value_type: "number", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
  let provider = @row_file.prepare_native_relation_file_provider(
    declaration,
    {
      directory,
      name: "original.json",
      resource: "records",
      items_path: ["items"],
      key_path: None,
      primary_identity: "id",
    },
    {
      page: { max_bytes: 4096, max_nodes: 128, max_depth: 8, max_rows: 1, },
      max_work: 1000000,
      chunk_bytes: 32,
      diagnostic_ceiling: 256,
    },
  ).unwrap()
  let sqlite_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap_or_else(() => {
      abort("file SQLite path")
    },
  )
  let library = @sqlite.load_library(sqlite_path).unwrap_or_else(() => {
    abort("file SQLite library")
  })
  let original_database = library
    .open_database(directory + "/client-file-receipt.sqlite3", 65536L)
    .unwrap_or_else(() => abort("file SQLite database"))
  let (database, journal, dispatch, preview, locator, key, basis) = receipt_test_dispatch(
    "client-file-receipt",
    file=true,
    original_database=Some(original_database),
  )
  let limits = native_client_effect_storage_profile.receipt
  let installation = @publication.effect_preview_member_source_binding_cid(
    preview, 0,
  ).unwrap()
  let target = @publication.effect_file_target_cid(
    installation,
    directory,
    "original.json",
    "records",
    "\"row-1\"",
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).unwrap()
  guard journal.lookup(dispatch.request, true) is Ok(Retained(record)) else {
    fail("Run missing")
  }
  let operation = @publication.prepare_effect_file_operation(
    preview,
    0,
    0,
    installation,
    target,
    basis.canonical_request_cid,
    dispatch.dispatching.cid,
    @host.client_request_authority_scope_cid(dispatch.request),
    record.checkpoint.unwrap().resolution_cid.unwrap(),
    file_receipt_original_version,
  ).unwrap()
  // The actual durable dispatch above precedes this original physical child.
  let child = @row_file.prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "row-1",
    update=Some(
      (file_receipt_original_version, "{\"value\":9}", "original-stage"),
    ),
  ).unwrap()
  assert_true(child.replacement_acknowledgment() is None)
  let mut complete = false
  for _ in 0..<100 {
    if child.advance().unwrap() {
      complete = true
      break
    }
  }
  assert_true(complete)
  let ack = child.replacement_acknowledgment().unwrap()
  assert_true(child.close().unwrap())
  assert_true(child.advance() is Err(_))
  let outcome = "{\"result\":{\"id\":\"row-1\"},\"state\":\"applied\"}"
  // Neither a missing current Read nor another Resolution can store this ACK.
  assert_true(
    journal.record_effect_file_response(
      dispatch,
      preview,
      0,
      0,
      operation,
      ack,
      outcome,
      () => false,
      4096,
    )
    is Err(AuthorizationDenied),
  )
  let foreign = @publication.prepare_effect_file_operation(
    preview,
    0,
    0,
    installation,
    target,
    basis.canonical_request_cid,
    dispatch.dispatching.cid,
    @host.client_request_authority_scope_cid(dispatch.request),
    "sha256:" + "0".repeat(64),
    file_receipt_original_version,
  ).unwrap()
  assert_true(
    journal.record_effect_file_response(
      dispatch,
      preview,
      0,
      0,
      foreign,
      ack,
      outcome,
      () => true,
      4096,
    )
    is Err(CustodyLost),
  )
  journal
  .record_effect_file_response(
    dispatch,
    preview,
    0,
    0,
    operation,
    ack,
    outcome,
    () => true,
    4096,
  )
  .unwrap()
  journal
  .record_effect_file_response(
    dispatch,
    preview,
    0,
    0,
    operation,
    ack,
    outcome,
    () => true,
    4096,
  )
  .unwrap()
  // The HTTP facade cannot invent a status or credential use for this record.
  assert_true(
    journal.effect_row_response(dispatch, () => true, 4096)
    is Err(Checkpoint(InvalidMaterial)),
  )
  journal.record_effect_row_unknown(dispatch).unwrap() |> ignore
  assert_true(
    journal.record_effect_row_receipt(
      dispatch,
      preview,
      0,
      0,
      locator,
      key,
      basis.canonical_request_cid,
      "{\"result\":{},\"state\":\"applied\"}",
      () => true,
      4096,
    )
    is Err(_),
  )
  let (receipt, terminal) = journal
    .record_effect_row_receipt(
      dispatch,
      preview,
      0,
      0,
      locator,
      key,
      basis.canonical_request_cid,
      outcome,
      () => true,
      4096,
    )
    .unwrap()
  assert_eq(@effect.effect_ledger_entry_state_code(terminal), 2)
  let (saved, head) = journal
    .effect_row_receipt(
      dispatch,
      preview,
      0,
      0,
      locator,
      key,
      basis.canonical_request_cid,
      () => true,
      4096,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    @publication.publication_contract_identity(saved),
    @publication.publication_contract_identity(receipt),
  )
  assert_eq(head.cid, terminal.cid)
  let saved_response = read_client_effect_response_record(
      database,
      dispatch.dispatching.cid,
    )
    .unwrap()
    .unwrap()
  assert_eq(saved_response.body, ack.replacement())
  assert_true(saved_response.protocol is FileOriginal(_))
  // Losing both rows cannot turn the recorded physical outcome back to unsent.
  // Exact retirement requires an original transaction, even for this fixture.
  database
  .begin_immediate()
  .unwrap_or_else(() => abort("file custody-loss transaction"))
  database
  .remove_exact(
    "client_effect_response_meta",
    dispatch.dispatching.cid,
    0L,
    saved_response.metadata,
  )
  .unwrap()
  database
  .remove_exact(
    "client_effect_response_bytes",
    dispatch.dispatching.cid,
    0L,
    saved_response.body,
  )
  .unwrap()
  database.commit().unwrap_or_else(() => abort("file custody-loss commit"))
  assert_true(journal.lookup(dispatch.request, true) is Err(CustodyLost))
  database.close_checked().unwrap()
}

///|
test "Native file ACK and exact bytes settle the same dispatch without HTTP or resend" {
  let directory = @env.get_env_var("ACTQL_TEST_NATIVE_FILE_RECEIPT_ROOT").unwrap()
  let path = @utf8.encode(directory + "/backing\u{0000}")
  let descriptor = file_receipt_fixture_open(path, 2)
  assert_true(descriptor >= 0)
  let parent_bytes = 384L * 1024L * 1024L
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    parent_bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: parent_bytes,
    },
    65536L,
  ).unwrap()
  arena.acquire_fd(descriptor).unwrap()
  let backing = arena.borrow_backing().unwrap()
  arena.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    arena
    .prepare_domain(backing, descriptor, 256L * 1024L * 1024L, {
      planning_work: 8,
      attempts: 4,
      holdings: 2,
      transfer_bytes: 16384L,
      retained_bytes: 16L * 1024L * 1024L,
      execution_bytes: 64L * 1024L * 1024L,
    })
    .unwrap() {
    @arena.PreparedDomain(value) => value
    _ => fail("file receipt fixture domain refused")
  }
  arena.transfer_domain(domain).unwrap()
  arena.leave_backing_borrow_scope(backing).unwrap()
  arena.return_backing_borrow(backing).unwrap()
  arena.prepare_domain_read(domain).unwrap()
  let execution = match
    arena.prepare_domain_retained_execution(domain).unwrap() {
    @arena.ReadyRetainedExecution(value) => value
    _ => fail("file receipt fixture execution partial")
  }
  arena.enter_domain_retained_execution(execution).unwrap()
  file_receipt_fixture_work(directory)
  arena.leave_domain_retained_execution(execution).unwrap()
  arena.close_domain_retained_execution(execution).unwrap()
  arena.close_domain_after_owner_ack(domain).unwrap()
  arena.try_close().unwrap()
  assert_eq(file_receipt_fixture_close(descriptor), 0)
}
