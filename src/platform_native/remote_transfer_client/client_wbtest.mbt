///|
fn native_transfer_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn native_transfer_request(
  chunks : Array[Bytes],
  route : @transfer.RemoteTransferRoute,
) -> @transfer.RemoteTransferRequest {
  let mut referenced_bytes = 0L
  for chunk in chunks {
    referenced_bytes = referenced_bytes + chunk.length().to_int64()
  }
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    native_transfer_cid("1"),
    native_transfer_cid("2"),
    native_transfer_cid("3"),
    chunks.length(),
    chunks.map(chunk => "sha256:" + @sha.hex(chunk)),
    chunks.map(chunk => chunk.length().to_int64()),
    chunks.map(_ => 1),
    8,
    4096,
    referenced_bytes,
  ).unwrap()
  @transfer.prepare_request(
    "native-coordinator",
    "native-transfer-1",
    route,
    "native-source",
    2,
    "native-destination",
    3,
    "native-source-material",
    manifest,
    referenced_bytes,
    4102444800000L,
    native_transfer_cid("4"),
    native_transfer_cid("5"),
    native_transfer_cid("6"),
  ).unwrap()
}

///|
fn native_direct_request(
  chunks : Array[Bytes],
) -> @transfer.RemoteTransferRequest {
  native_transfer_request(chunks, @transfer.DirectStream)
}

///|
test "native direct client sends admitted chunks over mTLS" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/direct-transfer.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let chunks = [b"alpha", @utf8.encode("日本語")]
  let request = native_direct_request(chunks)
  let record = send_durable_direct_transfer(
    journal, client, origin, request, chunks,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(record))
  assert_eq(
    @transfer.record_request_identity(record),
    @transfer.request_cid(request),
  )
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let restored = send_durable_direct_transfer(
    reopened, client, origin, request, chunks,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(restored))
  assert_true(reopened.close())
  assert_true(client.close())
}

///|
test "native direct client rejects altered chunks before network use" {
  let request = native_direct_request([b"alpha"])
  guard admit_direct_source(request, [b"other"]) is Err(SourceMismatch) else {
    fail("altered source chunk was accepted")
  }
}

///|
test "native direct failure persists confirmed remote cleanup" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal = @journal.open_journal(
    sqlite,
    sqlite_root + "/direct-transfer-cancel.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let chunks = [b"cancel-source"]
  let request = native_direct_request(chunks)
  guard send_durable_direct_transfer(journal, client, origin, request, chunks)
    is Err(Rejected(400)) else {
    fail("native direct failure did not preserve the physical rejection")
  }
  let cancelled = journal.require(request).unwrap()
  assert_true(@transfer.direct_transfer_cleanup_confirmed(cancelled))
  let restored = cancel_durable_direct_transfer(
    journal, client, origin, request,
  ).unwrap()
  assert_true(@transfer.direct_transfer_cleanup_confirmed(restored))
  assert_true(journal.close())
  assert_true(client.close())
}

///|
test "native direct retry reconciles a lost commit reply" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal = @journal.open_journal(
    sqlite,
    sqlite_root + "/direct-transfer-commit-loss.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let chunks = [b"commit-loss"]
  let request = native_direct_request(chunks)
  assert_true(
    send_durable_direct_transfer(journal, client, origin, request, chunks)
    is Err(ReconciliationRequired),
  )
  let uncertain = journal.require(request).unwrap()
  assert_eq(
    @transfer.direct_transfer_progress(uncertain),
    @transfer.DirectTransferCopying,
  )
  assert_false(@transfer.direct_transfer_cleanup_confirmed(uncertain))
  let committed = send_durable_direct_transfer(
    journal,
    client,
    origin,
    request,
    [],
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(committed))
  assert_true(journal.close())
  assert_true(client.close())
}

///|
test "native Store upload seals once and restores without source upload" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/store-upload.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let chunks = [b"store-alpha", @utf8.encode("保存")]
  let request = native_transfer_request(chunks, @transfer.TransferStore)
  let record = send_durable_store_upload(
    journal, client, origin, request, chunks,
  ).unwrap()
  assert_eq(
    @transfer.store_upload_progress(record),
    @transfer.StoreUploadSealed,
  )
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let restored = send_durable_store_upload(reopened, client, origin, request, []).unwrap()
  assert_eq(
    @transfer.store_upload_progress(restored),
    @transfer.StoreUploadSealed,
  )
  assert_true(reopened.close())
  let destination_root = @filesystem.open_root(store_root).unwrap()
  let failed_path = sqlite_root + "/store-destination-failed.sqlite"
  let failed_destination = @journal.open_journal(
    sqlite, failed_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  match
    receive_durable_store_transfer(
      failed_destination, client, destination_root, origin, request, "native-store-cancel",
      1048576L, 8L,
    ) {
    Err(SourceMismatch) => ()
    Err(Rejected(status)) =>
      fail("native Store failure setup: rejected " + status.to_string())
    Err(InvalidRequest) => fail("native Store failure setup: invalid request")
    Err(Physical(_)) => ()
    Err(Durable(_)) => fail("native Store failure setup: journal failure")
    Err(Destination(_)) =>
      fail("native Store failure setup: destination failure")
    Err(Protocol(_)) => fail("native Store failure setup: protocol failure")
    Err(ReconciliationRequired) =>
      fail("native Store failure setup: reconciliation required")
    Ok(_) => fail("native Store failure setup unexpectedly succeeded")
  }
  let cancelled = cancel_durable_store_transfer(
    failed_destination, client, destination_root, origin, request, "native-store-cancel",
  ).unwrap()
  assert_eq(@transfer.record_projection(cancelled)[1], 4)
  assert_eq(@transfer.record_projection(cancelled)[4], 1)
  assert_eq(
    failed_destination.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  assert_true(failed_destination.close())
  let destination_path = sqlite_root + "/store-destination.sqlite"
  let destination = @journal.open_journal(
    sqlite, destination_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let completed = match
    receive_durable_store_transfer(
      destination, client, destination_root, origin, request, "native-store-use",
      1048576L, 8L,
    ) {
    Ok(value) => value
    Err(InvalidRequest) => fail("native Store download: invalid request")
    Err(SourceMismatch) => fail("native Store download: source mismatch")
    Err(Rejected(status)) =>
      fail("native Store download: rejected " + status.to_string())
    Err(Physical(_)) => fail("native Store download: HTTP failure")
    Err(Durable(_)) => fail("native Store download: journal failure")
    Err(Destination(_)) => fail("native Store download: destination failure")
    Err(Protocol(_)) => fail("native Store download: protocol failure")
    Err(ReconciliationRequired) =>
      fail("native Store download: reconciliation required")
  }
  assert_true(@transfer.record_is_destination_committed(completed))
  assert_true(destination.close())
  let destination_reopened = @journal.open_journal(
    sqlite, destination_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let completed_again = receive_durable_store_transfer(
    destination_reopened, client, destination_root, origin, request, "native-store-use",
    1048576L, 8L,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(completed_again))
  assert_true(destination_reopened.close())
  assert_true(client.close())
}
