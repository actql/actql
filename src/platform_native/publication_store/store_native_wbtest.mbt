///|
fn native_payload_cid(label : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(label))
}

///|
fn native_payload_request(
  authority : String,
  token : String,
  max_bytes : Int64,
  row_count? : Int64 = 2L,
) -> @payload.PublicationPayloadRequest {
  @payload.prepare_publication_payload_request(
    authority,
    native_payload_cid(token + "-attempt"),
    native_payload_cid(token + "-material"),
    native_payload_cid(token + "-definition"),
    native_payload_cid(token + "-relation"),
    native_payload_cid(token + "-schema"),
    native_payload_cid(token + "-ordering"),
    native_payload_cid(token + "-codec"),
    max_bytes,
    row_count,
  ).unwrap()
}

///|
fn native_delivery_all(
  stream : PayloadDelivery,
  chunk_bytes : Int,
) -> (String, NativePublicationDeliverySummary) {
  let output : Array[Byte] = []
  while true {
    let chunk = stream.next(chunk_bytes).unwrap()
    for byte in chunk.bytes {
      output.push(byte)
    }
    if chunk.eof {
      break
    }
  }
  let summary = stream.finish().unwrap()
  (@utf8.decode_lossy(Bytes::from_array(output)), summary)
}

///|
fn native_payload_fixture(
  label : String,
  capacity_bytes : Int64,
) -> (Store, String, @sqlite.Library)? {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return None
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return None
  }
  let token = label + "-" + @env.now().to_string()
  let authority = native_payload_cid(token + "-authority")
  let library = @sqlite.load_library(library_path).unwrap()
  let store = open_store(library, root, authority, capacity_bytes, 8L, 65536L).unwrap()
  Some((store, authority, library))
}

///|
test "native publication payload streams, verifies and reclaims exactly" {
  guard native_payload_fixture("stream", 16L) is Some((store, authority, _)) else {
    return
  }
  let request = native_payload_request(authority, @env.now().to_string(), 16L)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"abc").unwrap()
  writer.append(b"def").unwrap()
  let info = writer.seal().unwrap()
  assert_eq(info.generation.size, 6L)
  assert_eq(info.row_count, 2L)
  let usage = store.capacity_usage().unwrap()
  assert_eq(usage.reserved_bytes, 16L)
  assert_eq(usage.reserved_objects, 1L)
  let reader = store.open_payload_reader(info.material_generation_cid).unwrap()
  assert_true(
    store.reclaim_payload(info.material_generation_cid) is Err(ReaderBusy),
  )
  assert_eq(reader.next(2).unwrap().bytes, b"ab")
  assert_eq(reader.next(4).unwrap().bytes, b"cdef")
  assert_true(reader.next(4).unwrap().eof)
  reader.finish().unwrap()
  store.reclaim_payload(info.material_generation_cid).unwrap()
  let released = store.capacity_usage().unwrap()
  assert_eq(released.reserved_bytes, 0L)
  assert_eq(released.reserved_objects, 0L)
  assert_true(store.close().unwrap())
}

///|
test "native publication payload survives restart and recovers cancellation" {
  guard native_payload_fixture("restart", 32L)
    is Some((store, authority, library)) else {
    return
  }
  let first_request = native_payload_request(
    authority,
    "retained-" + @env.now().to_string(),
    16L,
  )
  let first = store.begin_payload(first_request).unwrap()
  first.append(b"retained").unwrap()
  let retained = first.seal().unwrap()
  let cancelled_request = native_payload_request(
    authority,
    "cancelled-" + @env.now().to_string(),
    16L,
  )
  let cancelled = store.begin_payload(cancelled_request).unwrap()
  cancelled.append(b"partial").unwrap()
  cancelled.cancel().unwrap()
  assert_true(store.close().unwrap())
  let reopened = open_store(
    library,
    @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap(),
    authority,
    32L,
    8L,
    65536L,
  ).unwrap()
  let recovery = reopened.recover().unwrap()
  assert_eq(recovery.retained, 1)
  assert_eq(recovery.reclaimed, 0)
  let reader = reopened
    .open_payload_reader(retained.material_generation_cid)
    .unwrap()
  assert_eq(reader.next(32).unwrap().bytes, b"retained")
  reader.finish().unwrap()
  reopened.reclaim_payload(retained.material_generation_cid).unwrap()
  assert_true(reopened.close().unwrap())
}

///|
test "native publication capacity rejects before payload allocation" {
  guard native_payload_fixture("capacity", 8L) is Some((store, authority, _)) else {
    return
  }
  let first_request = native_payload_request(
    authority,
    "capacity-a-" + @env.now().to_string(),
    8L,
  )
  let first = store.begin_payload(first_request).unwrap()
  let second_request = native_payload_request(
    authority,
    "capacity-b-" + @env.now().to_string(),
    1L,
  )
  assert_true(
    store.begin_payload(second_request)
    is Err(Database(@sqlite.CapacityExceeded)),
  )
  first.cancel().unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "native publication capacity is shared by every handle for one root" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let token = "shared-capacity-" + @env.now().to_string()
  let authority = native_payload_cid(token + "-authority")
  let library = @sqlite.load_library(library_path).unwrap()
  let first = open_store(library, root, authority, 8L, 8L, 65536L).unwrap()
  let second = open_store(library, root, authority, 8L, 8L, 65536L).unwrap()
  let writer = first
    .begin_payload(native_payload_request(authority, token + "-a", 8L))
    .unwrap()
  assert_true(
    second.begin_payload(native_payload_request(authority, token + "-b", 1L))
    is Err(Database(@sqlite.CapacityExceeded)),
  )
  writer.cancel().unwrap()
  assert_eq(second.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(first.close().unwrap())
  assert_true(second.close().unwrap())
}

///|
test "native publication delivers JSON JSONL and CSV without Node" {
  guard native_payload_fixture("delivery", 1024L) is Some((store, authority, _)) else {
    return
  }
  let token = "delivery-" + @env.now().to_string()
  let payload = "[{\"n\":1,\"t\":\"x\"},{\"n\":null,\"t\":\"日本語\"}]"
  let request = native_payload_request(authority, token, 256L)
  let writer = store.begin_payload(request).unwrap()
  writer.append(@utf8.encode(payload)).unwrap()
  let info = writer.seal().unwrap()
  let schema = "{\"n\":{\"nullable\":true,\"type\":\"integer\"}," +
    "\"t\":{\"nullable\":false,\"type\":\"string\"}}"
  let expected = [
    ("json", payload),
    ("jsonl", "{\"n\":1,\"t\":\"x\"}\n{\"n\":null,\"t\":\"日本語\"}\n"),
    ("csv", "\"n\",\"t\"\n1,\"x\"\n\\N,\"日本語\"\n"),
  ]
  for entry in expected {
    let stream = store
      .open_payload_delivery(
        info.material_generation_cid,
        entry.0,
        schema,
        ["n", "t"],
        5,
        256,
        32,
        8,
        1024L,
      )
      .unwrap()
    let (actual, summary) = native_delivery_all(stream, 3)
    assert_eq(actual, entry.1)
    assert_eq(summary.rows, 2L)
    assert_eq(summary.bytes, @utf8.encode(entry.1).length().to_int64())
    assert_eq(
      summary.delivery_digest,
      "sha256:" + @sha.text_hex(entry.1).unwrap(),
    )
  }
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

///|
test "empty native JSONL still reaches an explicit delivery end" {
  guard native_payload_fixture("empty-delivery", 128L)
    is Some((store, authority, _)) else {
    return
  }
  let token = "empty-delivery-" + @env.now().to_string()
  let request = native_payload_request(authority, token, 16L, row_count=0L)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"[]").unwrap()
  let info = writer.seal().unwrap()
  let stream = store
    .open_payload_delivery(
      info.material_generation_cid,
      "jsonl",
      "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}",
      ["n"],
      2,
      64,
      8,
      4,
      0L,
    )
    .unwrap()
  let terminal = stream.next(1).unwrap()
  assert_true(terminal.eof)
  assert_eq(terminal.bytes, b"")
  let summary = stream.finish().unwrap()
  assert_eq(summary.bytes, 0L)
  assert_eq(summary.rows, 0L)
  assert_eq(
    summary.delivery_digest,
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

///|
test "native delivery limit failure keeps its reader until explicit close" {
  guard native_payload_fixture("delivery-limit", 128L)
    is Some((store, authority, _)) else {
    return
  }
  let token = "delivery-limit-" + @env.now().to_string()
  let request = native_payload_request(authority, token, 64L, row_count=1L)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"[{\"n\":123}]").unwrap()
  let info = writer.seal().unwrap()
  let stream = store
    .open_payload_delivery(
      info.material_generation_cid,
      "json",
      "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}",
      ["n"],
      4,
      64,
      8,
      4,
      2L,
    )
    .unwrap()
  assert_eq(stream.next(1).unwrap().bytes, b"[")
  assert_true(stream.next(1) is Err(DeliveryLimit))
  assert_true(
    store.reclaim_payload(info.material_generation_cid) is Err(ReaderBusy),
  )
  stream.close().unwrap()
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}
