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
  assert_true(client.close())
}
