///|
fn journal_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn journal_manifest() -> @manifest.PhysicalManifest {
  @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    journal_cid("1"),
    journal_cid("2"),
    journal_cid("3"),
    1,
    [journal_cid("a")],
    [5L],
    [1],
    1,
    4096,
    5L,
  ).unwrap()
}

///|
fn journal_request(
  route : @transfer.RemoteTransferRoute,
) -> @transfer.RemoteTransferRequest {
  @transfer.prepare_request(
    "native-coordinator",
    "transfer-1",
    route,
    "source-a",
    1,
    "destination-b",
    2,
    "material-a",
    journal_manifest(),
    5L,
    2000000000000L,
    journal_cid("4"),
    journal_cid("5"),
    journal_cid("6"),
  ).unwrap()
}

///|
test "native Transfer journal rejects conflicting occurrence content" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root + "/transfer-" + @env.now().to_string() + ".sqlite3"
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let second = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let request = journal_request(@transfer.DirectStream)
  let (kind, record) = first.accept(request).unwrap()
  assert_eq(kind, NewTransfer)
  assert_eq(second.accept(request).unwrap().0, ExistingTransfer)
  assert_true(
    second.accept(journal_request(@transfer.TransferStore))
    is Err(StateCollision),
  )
  let start = @transfer.prepare_start(record).unwrap()
  first.commit_transition(start).unwrap()
  assert_eq(@transfer.record_revision(second.require(request).unwrap()), 1)
  first.close() |> ignore
  second.close() |> ignore
}

///|
test "native Transfer journal recovers exact durable state after reopen" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/transfer-reopen-" +
    @env.now().to_string() +
    ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let (_, record) = first.accept(request).unwrap()
  first.commit_transition(@transfer.prepare_start(record).unwrap()).unwrap()
  first
  .commit_transition(@transfer.prepare_failure(record, false, true).unwrap())
  .unwrap()
  first.close() |> ignore
  let reopened = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let recovered = reopened.recover_after("").unwrap().unwrap()
  assert_eq(
    recovered_remote_transfer_key(recovered),
    @transfer.request_journal_identity(request).unwrap(),
  )
  assert_eq(
    @transfer.record_projection(recovered_remote_transfer_record(recovered)),
    [2, 3, 2, 0, 0, 1, 0, 0, 0],
  )
  reopened.close() |> ignore
}

///|
test "native Store use journal restores exact download progress" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root + "/store-use-" + @env.now().to_string() + ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let (_, record) = first.accept_store_use(request, "native-use").unwrap()
  first
  .commit_store_use_transition(
    @transfer.prepare_store_use_start(record).unwrap(),
  )
  .unwrap()
  first
  .commit_store_use_transition(
    @transfer.prepare_store_use_progress(record, 1, 5L).unwrap(),
  )
  .unwrap()
  first.close() |> ignore
  let reopened = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let store_use = @transfer.prepare_store_use(request, "native-use").unwrap()
  assert_eq(
    @transfer.store_use_record_projection(
      reopened.require_store_use(store_use).unwrap(),
    ),
    ["2", "1", "0", "1", "5", "0", ""],
  )
  reopened.close() |> ignore
}

///|
test "destination request fixes one durable Store use before capacity" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/destination-use-" +
    @env.now().to_string() +
    ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  let second = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  ignore(first.accept(request).unwrap())
  assert_true(first.bind_destination_use(request, "use-a").unwrap())
  assert_false(second.bind_destination_use(request, "use-a").unwrap())
  assert_true(
    second.bind_destination_use(request, "use-b") is Err(StateCollision),
  )
  assert_true(first.reserve_destination_holding(request, 5L, 1L).unwrap())
  assert_eq(second.destination_capacity_usage().unwrap().reserved_bytes, 5L)
  assert_true(second.release_destination_holding(request).unwrap())
  assert_eq(first.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(first.close())
  assert_true(second.close())
  let reopened = open_journal(library, database_path, 262144L, 1, 4096, 5L).unwrap()
  assert_false(reopened.bind_destination_use(request, "use-a").unwrap())
  assert_true(
    reopened.bind_destination_use(request, "use-b") is Err(StateCollision),
  )
  assert_true(reopened.close())
}

///|
test "committed destination readers durably block reclaim" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    return
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/destination-readers-" +
    @env.now().to_string() +
    ".sqlite3"
  let request = journal_request(@transfer.TransferStore)
  let first = open_journal(
    library,
    database_path,
    262144L,
    1,
    4096,
    5L,
    max_destination_readers=2L,
  ).unwrap()
  let second = open_journal(
    library,
    database_path,
    262144L,
    1,
    4096,
    5L,
    max_destination_readers=2L,
  ).unwrap()
  let (_, record) = first.accept(request).unwrap()
  first.commit_transition(@transfer.prepare_start(record).unwrap()).unwrap()
  first
  .commit_transition(
    @transfer.prepare_source_settled(record, true, true).unwrap(),
  )
  .unwrap()
  first
  .commit_transition(@transfer.prepare_destination_commit(record).unwrap())
  .unwrap()
  let receipt = @transfer.prepare_destination_receipt(
    request, "destination-material-a",
  ).unwrap()
  first.commit_destination_receipt(receipt, request).unwrap() |> ignore
  assert_true(first.reserve_destination_holding(request, 5L, 1L).unwrap())
  assert_true(
    first.validate_destination_reader(request, receipt, "reader-a")
    is Err(RecoveryRequired),
  )
  // Validation neither restores a missing material nor consumes a reader slot.
  assert_eq(first.destination_capacity_usage().unwrap().reserved_bytes, 5L)
  match first.acquire_destination_reader(request, receipt, "reader-a") {
    Ok(value) => assert_true(value)
    Err(UnsupportedTarget) => fail("destination reader target unsupported")
    Err(Closed) => fail("destination reader journal closed")
    Err(Physical(_)) => fail("destination reader physical failure")
    Err(Protocol(_)) => fail("destination reader protocol failure")
    Err(StateCollision) => fail("destination reader state collision")
    Err(RecoveryRequired) => fail("destination reader requires recovery")
    Err(MaterialInUse) => fail("destination reader unexpectedly in use")
  }
  first.validate_destination_reader(request, receipt, "reader-a").unwrap()
  second.validate_destination_reader(request, receipt, "reader-a").unwrap()
  let foreign = @transfer.prepare_destination_receipt(request, "other-material").unwrap()
  assert_true(
    first.validate_destination_reader(request, foreign, "reader-a")
    is Err(StateCollision),
  )
  assert_true(
    first.validate_destination_reader(request, receipt, "absent-reader")
    is Err(RecoveryRequired),
  )
  assert_false(
    second.acquire_destination_reader(request, receipt, "reader-a").unwrap(),
  )
  assert_true(
    second.begin_destination_material_reclaim(request, receipt)
    is Err(MaterialInUse),
  )
  assert_true(
    second.release_destination_reader(request, receipt, "reader-a").unwrap(),
  )
  assert_true(
    first.validate_destination_reader(request, receipt, "reader-a")
    is Err(RecoveryRequired),
  )
  assert_false(
    first.release_destination_reader(request, receipt, "reader-a").unwrap(),
  )
  assert_true(
    first.begin_destination_material_reclaim(request, receipt).unwrap(),
  )
  assert_false(
    second.begin_destination_material_reclaim(request, receipt).unwrap(),
  )
  assert_true(
    first.acquire_destination_reader(request, receipt, "reader-b")
    is Err(RecoveryRequired),
  )
  assert_true(
    first.finish_destination_material_reclaim(request, receipt, false)
    is Err(RecoveryRequired),
  )
  assert_true(
    first.finish_destination_material_reclaim(request, receipt, true).unwrap(),
  )
  assert_false(
    second.finish_destination_material_reclaim(request, receipt, true).unwrap(),
  )
  assert_false(
    first.begin_destination_material_reclaim(request, receipt).unwrap(),
  )
  assert_eq(first.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(first.close())
  assert_true(second.close())
  let reopened = open_journal(
    library,
    database_path,
    262144L,
    1,
    4096,
    5L,
    max_destination_readers=2L,
  ).unwrap()
  assert_true(
    reopened.validate_destination_reader(request, receipt, "reader-a")
    is Err(RecoveryRequired),
  )
  assert_true(
    reopened.acquire_destination_reader(request, receipt, "reader-c")
    is Err(RecoveryRequired),
  )
  assert_true(reopened.close())
}
