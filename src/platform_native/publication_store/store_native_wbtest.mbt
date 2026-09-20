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
fn native_bound_payload_request(
  authority : String,
  token : String,
  schema_cid : String,
  ordering_cid : String,
  codec_cid : String,
  max_bytes : Int64,
  row_count : Int64,
) -> @payload.PublicationPayloadRequest {
  @payload.prepare_publication_payload_request(
    authority,
    native_payload_cid(token + "-attempt"),
    native_payload_cid(token + "-material"),
    native_payload_cid(token + "-definition"),
    native_payload_cid(token + "-relation"),
    schema_cid,
    ordering_cid,
    codec_cid,
    max_bytes,
    row_count,
  ).unwrap()
}

///|
fn native_contract(
  name : String,
  body : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(name, body, 65536, 512, 16).unwrap()
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
test "native delivery separates source reads from sink confirmation" {
  guard native_payload_fixture("confirmed-delivery", 128L)
    is Some((store, authority, _)) else {
    return
  }
  let token = "confirmed-delivery-" + @env.now().to_string()
  let request = native_payload_request(authority, token, 64L, row_count=1L)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"[{\"n\":1}]").unwrap()
  let info = writer.seal().unwrap()
  let stream = store
    .open_confirmed_payload_delivery(
      info.material_generation_cid,
      "jsonl",
      "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}",
      ["n"],
      3,
      64,
      8,
      4,
      64L,
    )
    .unwrap()
  let first = stream.next(4).unwrap()
  assert_true(
    stream.next(4)
    is Err(SinkProgress(@publication.DeliverySinkChunkOutstanding)),
  )
  assert_eq(stream.confirm_chunk().unwrap(), first.bytes.length().to_int64())
  let output : Array[Byte] = []
  for byte in first.bytes {
    output.push(byte)
  }
  while true {
    let chunk = stream.next(4).unwrap()
    for byte in chunk.bytes {
      output.push(byte)
    }
    if chunk.bytes.length() > 0 {
      ignore(stream.confirm_chunk().unwrap())
    }
    if chunk.eof {
      break
    }
  }
  let summary = stream.confirm_sink_finished().unwrap()
  let expected = "{\"n\":1}\n"
  assert_eq(@utf8.decode_lossy(Bytes::from_array(output)), expected)
  assert_eq(summary.bytes, @utf8.encode(expected).length().to_int64())
  assert_eq(
    summary.delivery_digest,
    "sha256:" + @sha.text_hex(expected).unwrap(),
  )
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

///|
test "empty native delivery needs explicit sink finish confirmation" {
  guard native_payload_fixture("confirmed-empty", 128L)
    is Some((store, authority, _)) else {
    return
  }
  let token = "confirmed-empty-" + @env.now().to_string()
  let request = native_payload_request(authority, token, 16L, row_count=0L)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"[]").unwrap()
  let info = writer.seal().unwrap()
  let stream = store
    .open_confirmed_payload_delivery(
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
  let summary = stream.confirm_sink_finished().unwrap()
  assert_eq(summary.bytes, 0L)
  assert_eq(
    summary.delivery_digest,
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  store.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(store.close().unwrap())
}

///|
test "native formal delivery durably binds attempt receipt and success" {
  guard native_payload_fixture("formal-delivery", 256L)
    is Some((store, authority, library)) else {
    return
  }
  let token = "formal-delivery-" + @env.now().to_string()
  let schema_wire = "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}"
  let schema_cid = "sha256:8eb90081d3d6698fc88cf5ba2d9c906b9f28f67e03693d8919b4e5c11e4ed80f"
  let ordering_cid = native_payload_cid(token + "-ordering")
  let codec_cid = native_payload_cid(token + "-codec")
  let request = native_bound_payload_request(
    authority, token, schema_cid, ordering_cid, codec_cid, 64L, 1L,
  )
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"[{\"n\":1}]").unwrap()
  let info = writer.seal().unwrap()
  let run_definition_cid = native_payload_cid(token + "-run")
  let invocation_cid = native_payload_cid(token + "-invocation")
  let retention = native_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    native_payload_cid(token + "-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    native_payload_cid(token + "-data-policy") +
    "\",\"available_until\":\"2026-09-21T00:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-22T00:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-22T00:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    native_payload_cid(token + "-metadata-policy") +
    "\",\"metadata_delete_by\":\"2026-09-23T00:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    native_payload_cid(token + "-clock") +
    "\"}",
  )
  let artifact = native_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    info.result_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"logical_result_cid\":\"" +
    info.logical_relation_cid +
    "\",\"result_schema_cid\":\"" +
    info.result_schema_cid +
    "\",\"ordering_evidence_cid\":\"" +
    info.ordering_evidence_cid +
    "\",\"actual_row_count\":1,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    native_payload_cid(token + "-data-policy") +
    "\",\"effective_retention_policy_cid\":\"" +
    @publication.publication_contract_identity(retention) +
    "\",\"provenance_evidence_cids\":[]}",
  )
  let manifest = native_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"results\":{\"answer\":" +
    @publication.publication_contract_json(artifact) +
    "}}",
  )
  let binding = native_contract(
    "durable_result_binding",
    "{\"version\":\"actql-durable-result-binding/0.1\"," +
    "\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"result_definition_cid\":\"" +
    info.result_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"logical_result_cid\":\"" +
    info.logical_relation_cid +
    "\",\"result_schema_cid\":\"" +
    info.result_schema_cid +
    "\",\"ordering_evidence_cid\":\"" +
    info.ordering_evidence_cid +
    "\",\"codec_contract_cid\":\"" +
    info.durable_codec_cid +
    "\",\"result_fields\":[\"n\"],\"material_generation_cid\":\"" +
    info.material_generation_cid +
    "\",\"store_authority_cid\":\"" +
    authority +
    "\",\"effective_retention_policy_cid\":\"" +
    @publication.publication_contract_identity(retention) +
    "\",\"row_count\":1,\"byte_count\":" +
    info.generation.size.to_string() +
    ",\"physical_sha256\":\"" +
    info.physical_digest[7:].to_owned() +
    "\"}",
  )
  let index = native_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\"," +
    "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
    native_payload_cid(token + "-scope") +
    "\",\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"result_manifest_cid\":\"" +
    @publication.publication_contract_identity(manifest) +
    "\",\"run_receipt_cid\":\"" +
    native_payload_cid(token + "-receipt") +
    "\",\"captured_run_cid\":\"" +
    native_payload_cid(token + "-captured") +
    "\",\"durable_result_binding_cids\":[\"" +
    @publication.publication_contract_identity(binding) +
    "\"],\"publication_request_cid\":\"" +
    native_payload_cid(token + "-publication-request") +
    "\",\"publication_attempt_cid\":\"" +
    native_payload_cid(token + "-publication-attempt") +
    "\",\"committed_at\":\"2026-09-20T00:00:00.000Z\"}",
  )
  let grant = @publication.issue_result_read_grant(
    index,
    manifest,
    ["answer"],
    ["jsonl"],
    "principal",
    "download",
    native_payload_cid(token + "-ceiling"),
    64,
    2,
    "2026-09-21T00:00:00.000Z",
    native_payload_cid(token + "-authorization"),
    native_payload_cid(token + "-egress"),
    65536,
    512,
    16,
  ).unwrap()
  let success_attempt_id = token + "-delivery-attempt"
  let delivery = store
    .begin_result_delivery(
      index,
      manifest,
      grant,
      retention,
      binding,
      info.material_generation_cid,
      "answer",
      "jsonl",
      success_attempt_id,
      "2026-09-20T01:00:00.000Z",
      schema_wire,
      ["n"],
      3,
      64,
      65536,
      512,
      16,
      64L,
    )
    .unwrap()
  let delivered : Array[Byte] = []
  while true {
    let chunk = delivery.next(3, "2026-09-20T01:00:01.000Z").unwrap()
    for byte in chunk.bytes {
      delivered.push(byte)
    }
    if chunk.bytes.length() > 0 {
      ignore(delivery.confirm_chunk().unwrap())
    }
    if chunk.eof {
      break
    }
  }
  let success = delivery
    .confirm_sink_finished("2026-09-20T01:00:02.000Z")
    .unwrap()
  assert_eq(@utf8.decode_lossy(Bytes::from_array(delivered)), "{\"n\":1}\n")
  assert_eq(success.confirmed_bytes, 8L)
  assert_eq(success.delivered_sha256, @sha.text_hex("{\"n\":1}\n").unwrap())
  assert_true(success.delivery_attempt_cid == delivery.attempt_cid())
  assert_true(
    store.begin_result_delivery(
      index,
      manifest,
      grant,
      retention,
      binding,
      info.material_generation_cid,
      "answer",
      "jsonl",
      success_attempt_id,
      "2026-09-20T01:00:00.000Z",
      schema_wire,
      ["n"],
      3,
      64,
      65536,
      512,
      16,
      64L,
    )
    is Err(ExistingDeliveryAttempt),
  )
  let cancelled_attempt_id = token + "-cancelled-attempt"
  let cancelled = store
    .begin_result_delivery(
      index,
      manifest,
      grant,
      retention,
      binding,
      info.material_generation_cid,
      "answer",
      "jsonl",
      cancelled_attempt_id,
      "2026-09-20T01:00:03.000Z",
      schema_wire,
      ["n"],
      3,
      64,
      65536,
      512,
      16,
      64L,
    )
    .unwrap()
  let exposed = cancelled.next(3, "2026-09-20T01:00:04.000Z").unwrap()
  assert_eq(exposed.bytes.length(), 3)
  let failure = cancelled
    .terminate(
      Some(1),
      true,
      "unknown_additional",
      Some(2),
      Some(native_payload_cid(token + "-failure")),
      "2026-09-20T01:00:05.000Z",
    )
    .unwrap()
  assert_eq(failure.state, "cancelled")
  assert_eq(failure.confirmed_bytes, 1L)
  let durable_success = store
    .inspect_result_delivery(success_attempt_id)
    .unwrap()
  assert_eq(durable_success.state, "succeeded")
  assert_eq(
    durable_success.result_delivery_receipt_cid,
    Some(success.result_delivery_receipt_cid),
  )
  let durable_failure = store
    .inspect_result_delivery(cancelled_attempt_id)
    .unwrap()
  assert_eq(durable_failure.state, "cancelled")
  assert_eq(durable_failure.confirmed_bytes, 1L)
  assert_true(store.close().unwrap())
  let reopened = open_store(
    library,
    @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap(),
    authority,
    256L,
    8L,
    65536L,
  ).unwrap()
  assert_true(
    reopened.begin_result_delivery(
      index,
      manifest,
      grant,
      retention,
      binding,
      info.material_generation_cid,
      "answer",
      "jsonl",
      token + "-exhausted-attempt",
      "2026-09-20T01:00:06.000Z",
      schema_wire,
      ["n"],
      3,
      64,
      65536,
      512,
      16,
      64L,
    )
    is Err(DeliveryGrantUsage(@publication.DeliveryGrantUsageExhausted)),
  )
  assert_eq(
    reopened.inspect_result_delivery(success_attempt_id).unwrap().state,
    "succeeded",
  )
  reopened.reclaim_payload(info.material_generation_cid).unwrap()
  assert_true(reopened.inspect_payload(info.material_generation_cid) is Err(_))
  assert_true(reopened.close().unwrap())
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
