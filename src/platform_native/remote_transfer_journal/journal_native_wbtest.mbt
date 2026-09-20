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
