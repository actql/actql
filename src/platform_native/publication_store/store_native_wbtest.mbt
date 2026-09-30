///|
#borrow(root)
extern "C" fn test_fail_root_sync(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

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
test "native publication Store refuses old and unidentified roots without writes" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_LEGACY_STORE_ROOT")
    is Some(legacy_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_UNKNOWN_STORE_ROOT")
    is Some(unknown_root) else {
    return
  }
  let library = @sqlite.load_library(library_path).unwrap()
  let authority = native_payload_cid("format-test-authority")
  guard open_store(library, legacy_root, authority, 64L, 8L, 65536L)
    is Err(LegacyStoreFormat(path)) &&
    path == legacy_root else {
    fail("legacy Store root was accepted or relabeled")
  }
  guard open_store(library, unknown_root, authority, 64L, 8L, 65536L)
    is Err(UnknownStoreFormat(path)) &&
    path == unknown_root else {
    fail("unidentified Store root was accepted or relabeled")
  }
}

///|
test "native publication payload streams, verifies and reclaims exactly" {
  guard native_payload_fixture("stream", 16L) is Some((store, authority, _)) else {
    return
  }
  let request = native_payload_request(authority, @env.now().to_string(), 16L)
  assert_true(store.reconcile_payload(request).unwrap() is None)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"abc").unwrap()
  writer.append(b"def").unwrap()
  let info = writer.seal().unwrap()
  guard store.reconcile_payload(request).unwrap() is Some(reconciled) else {
    fail("sealed payload was not reconciled")
  }
  assert_eq(reconciled.physical_digest, info.physical_digest)
  assert_eq(reconciled.generation, info.generation)
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
  guard reopened.reconcile_payload(first_request).unwrap() is Some(reconciled) else {
    fail("restarted payload was not reconciled")
  }
  assert_eq(reconciled.physical_digest, retained.physical_digest)
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
test "native publication Store root has one live recovery owner" {
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
  let writer = first
    .begin_payload(native_payload_request(authority, token + "-a", 8L))
    .unwrap()
  assert_true(
    open_store(library, root, authority, 8L, 8L, 65536L)
    is Err(Filesystem(@filesystem.Lock(_))),
  )
  writer.cancel().unwrap()
  assert_true(first.close().unwrap())
  let successor = open_store(library, root, authority, 8L, 8L, 65536L).unwrap()
  assert_eq(successor.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(successor.close().unwrap())
}

///|
test "native publication Store enforces cross-process root ownership" {
  guard @env.get_env_var("ACTQL_TEST_PUBLICATION_LOCK_MODE") is Some(mode) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let authority = native_payload_cid("cross-process-lock-authority")
  let library = @sqlite.load_library(library_path).unwrap()
  if mode == "held" {
    assert_true(
      open_store(library, root, authority, 8L, 8L, 65536L)
      is Err(Filesystem(@filesystem.Lock(_))),
    )
  } else if mode == "released" {
    let successor = open_store(library, root, authority, 8L, 8L, 65536L).unwrap()
    assert_true(successor.close().unwrap())
  } else {
    fail("invalid cross-process lock test mode")
  }
}

///|
test "native publication create conflict preserves the foreign staging allocation" {
  guard native_payload_fixture("foreign-staging", 64L)
    is Some((store, authority, _)) else {
    return
  }
  let request = native_payload_request(
    authority,
    "foreign-staging-" + @env.now().to_string(),
    32L,
  )
  let name = @payload.publication_payload_staging_name(request)
  let foreign = store.root.create_writer(name, 32L).unwrap()
  foreign.append(b"foreign").unwrap()
  let before = store.root.inspect_generation(name).unwrap().unwrap()
  assert_true(
    store.begin_payload(request) is Err(Filesystem(@filesystem.Conflict)),
  )
  assert_eq(store.root.inspect_generation(name).unwrap(), Some(before))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  foreign.cancel().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "native publication seal conflict reclaims only its owned staging allocation" {
  guard native_payload_fixture("foreign-object", 64L)
    is Some((store, authority, _)) else {
    return
  }
  let request = native_payload_request(
    authority,
    "foreign-object-" + @env.now().to_string(),
    32L,
  )
  let object_name = @payload.publication_payload_object_name(request)
  let foreign = store.root.create_writer(object_name, 32L).unwrap()
  foreign.append(b"foreign").unwrap()
  let before = store.root.inspect_generation(object_name).unwrap().unwrap()
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"owned").unwrap()
  assert_true(writer.seal() is Err(Filesystem(@filesystem.Conflict)))
  writer.cancel().unwrap()
  assert_eq(store.root.inspect_generation(object_name).unwrap(), Some(before))
  foreign.cancel().unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "native publication retains failed writer cleanup for Store retry" {
  guard native_payload_fixture("writer-cleanup", 64L)
    is Some((store, authority, _)) else {
    return
  }
  let request = native_payload_request(
    authority,
    "writer-cleanup-" + @env.now().to_string(),
    32L,
  )
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"partial").unwrap()
  let independent_request = native_payload_request(
    authority,
    "writer-cleanup-independent-" + @env.now().to_string(),
    32L,
  )
  let independent = store.begin_payload(independent_request).unwrap()
  independent.append(b"live").unwrap()
  test_fail_root_sync(store.root, 2)
  assert_true(writer.cancel() is Err(Filesystem(@filesystem.Cleanup(_))))
  let cleanup = store.acquire_payload_cleanup(request).unwrap()
  assert_true(cleanup.pending())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 64L)
  assert_true(cleanup.retry() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 64L)
  test_fail_root_sync(store.root, 0)
  assert_true(cleanup.retry().unwrap())
  assert_false(cleanup.pending())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 32L)
  independent.cancel().unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "native publication retries directory sync after payload unlink" {
  guard native_payload_fixture("reclaim-sync", 64L)
    is Some((store, authority, _)) else {
    return
  }
  let request = native_payload_request(
    authority,
    "reclaim-sync-" + @env.now().to_string(),
    32L,
  )
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"payload").unwrap()
  let info = writer.seal().unwrap()
  test_fail_root_sync(store.root, 2)
  assert_true(
    store.reclaim_payload(info.material_generation_cid)
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 32L)
  assert_true(
    store.reclaim_payload(info.material_generation_cid)
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 32L)
  assert_true(store.reclaim_payload(info.material_generation_cid) is Ok(_))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
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
priv struct NativePublicationCommitFixture {
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  derivations : Array[@publication.PublicationContract]
  orderings : Array[@publication.PublicationContract]
  retentions : Array[@publication.PublicationContract]
  bindings : Array[@publication.PublicationContract]
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  captured_run : @publication.PublicationContract
  request : @publication.PublicationContract
  attempt : @publication.PublicationContract
  index : @publication.PublicationContract
  authority_scope_cid : String
  material_generation_cid : String
  schema_wire : String
}

///|
fn native_commit_plan(
  program_cid : String,
  token : String,
) -> @publication.PublicationContract {
  native_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    native_payload_cid(token + "-executable") +
    "\",\"program_definition_cid\":\"" +
    program_cid +
    "\",\"program_semantics_cid\":\"" +
    native_payload_cid(token + "-semantics") +
    "\",\"aoa_contract_cid\":\"" +
    native_payload_cid(token + "-aoa-contract") +
    "\",\"aoa_logical_cid\":\"" +
    native_payload_cid(token + "-aoa-logical") +
    "\"}",
  )
}

///|
fn native_commit_evidence(
  name : String,
  body : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(name, body, 65536, 4096, 32).unwrap()
}

///|
fn native_commit_fixture(
  store : Store,
  store_authority_cid : String,
  token : String,
) -> NativePublicationCommitFixture {
  let program_cid = native_payload_cid(token + "-program")
  let template = native_commit_evidence(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"parameter_values_cid\":\"" +
    native_payload_cid(token + "-parameters") +
    "\",\"invocation_bindings_cid\":\"" +
    native_payload_cid(token + "-bindings") +
    "\",\"check_environment_cid\":\"" +
    native_payload_cid(token + "-environment") +
    "\",\"grammar_manifest_cid\":\"" +
    native_payload_cid(token + "-grammar") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    native_payload_cid(token + "-barriers") +
    "\",\"source_evidence\":\"unbound\"}",
  )
  let plan = native_commit_plan(program_cid, token)
  let execution_context_cid = native_payload_cid(token + "-execution")
  let host_policy_cid = native_payload_cid(token + "-host-policy")
  let prepared = native_commit_evidence(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(plan) +
    "\",\"execution_context_cid\":\"" +
    execution_context_cid +
    "\",\"host_policy_cid\":\"" +
    host_policy_cid +
    "\",\"policy_decision\":\"allow\"," +
    "\"expires_at\":\"2026-09-21T04:00:00.000Z\"}",
  )
  let authorization = native_commit_evidence(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    @publication.run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    execution_context_cid +
    "\",\"host_policy_cid\":\"" +
    host_policy_cid +
    "\",\"decision\":\"allowed\"}",
  )
  let admission = @publication.admit_run_publication(
    template, prepared, authorization, plan,
  ).unwrap()
  let run_definition = @publication.issue_run_definition(
    admission,
    "scope",
    token + "-run",
    native_payload_cid(token + "-inputs"),
    "2026-09-20T00:00:00.000Z",
    "2026-09-21T04:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let observation = native_commit_evidence(
    "observation_set",
    "{\"version\":\"actql-observation-set/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"source_evidence_cids\":[]," +
    "\"captured_input_artifact_cids\":[]," +
    "\"consistency\":\"no_external_sources\"," +
    "\"capture_started_at\":null,\"capture_completed_at\":null," +
    "\"replayability\":{\"materialized\":false," +
    "\"availability_evidence_cids\":[]},\"data_policy_cid\":\"" +
    native_payload_cid(token + "-observation-policy") +
    "\"}",
  )
  let invocation = @publication.issue_run_invocation(
    template, observation, 65536, 4096, 32,
  ).unwrap()
  let definition = @publication.result_definition_contract(
    @publication.prepare_result_definition(program_cid, "answer").unwrap(),
  )
  let row_wire = "[{\"value\":7}]"
  let schema_wire = "{\"value\":{\"nullable\":false,\"type\":\"integer\"}}"
  let rows_source = @source.parse_json(row_wire, {
    max_input_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }).unwrap()
  let rows = @json.from_source(rows_source, 4096, 32, 65536) catch {
    _ => abort("invalid native publication rows fixture")
  }
  let relation_writer = @encode.hashing_writer(65536, 4096, 32) catch {
    _ => abort("invalid native publication Relation writer")
  }
  let logical_cid = try {
    @encode.begin_object(relation_writer)
    @encode.key(relation_writer, "sort")
    @encode.string_value(relation_writer, "relation")
    @encode.key(relation_writer, "value")
    @json.emit_value(rows, relation_writer)
    @encode.end_object(relation_writer)
    let (digest, _, _) = @encode.finish_hash_usage(relation_writer)
    "sha256:" + digest
  } catch {
    _ => abort("invalid native publication Relation identity")
  }
  let schema_cid = native_payload_cid(schema_wire)
  let data_policy_cid = native_payload_cid(token + "-data-policy")
  let authority_scope_cid = native_payload_cid(token + "-authority-scope")
  let evidence = @publication.issue_result_occurrence_evidence(
    definition,
    logical_cid,
    schema_cid,
    native_payload_cid(token + "-compute"),
    [],
    native_payload_cid(token + "-result-scope"),
    data_policy_cid,
    "actql-native-host",
    authority_scope_cid,
    65536,
    4096,
    32,
  ).unwrap()
  let ordering = @publication.result_ordering_evidence_contract(evidence)
  let derivation = @publication.result_ordering_derivation_contract(evidence)
  let retention = native_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    native_payload_cid(token + "-retention") +
    "\",\"effective_data_policy_cid\":\"" +
    data_policy_cid +
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
  let artifact = @publication.issue_complete_result_artifact(
    definition, invocation, evidence, retention, 1, 65536, 4096, 32,
  ).unwrap()
  let manifest = @publication.issue_result_manifest(
    run_definition,
    invocation,
    [definition],
    [artifact],
    65536,
    4096,
    32,
  ).unwrap()
  let journal = native_commit_evidence(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\"," +
    "\"rule_catalog_cid\":\"" +
    native_payload_cid(token + "-rules") +
    "\",\"entries\":[]}",
  )
  let receipt = @publication.issue_effect_free_run_receipt(
    admission,
    run_definition,
    invocation,
    observation,
    [definition],
    [artifact],
    manifest,
    journal,
    [],
    [],
    [],
    [],
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let snapshot = match
    @publication.admit_captured_result_snapshot(
      definition,
      artifact,
      row_wire,
      ["value"],
      65536,
      4096,
      32,
    ) {
    Ok(value) => value
    Err(@publication.CaptureIssuanceReferenceMismatch(field)) =>
      abort("native publication snapshot reference: " + field)
    Err(@publication.CaptureIssuanceInvalidRows(field)) =>
      abort("native publication snapshot rows: " + field)
    Err(@publication.CaptureIssuanceInvalidFields(field)) =>
      abort("native publication snapshot fields: " + field)
    Err(_) => abort("invalid native publication snapshot")
  }
  let authoring = native_commit_evidence(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    program_cid +
    "\",\"annotations\":[]}",
  )
  let captured_run = @publication.issue_effect_free_captured_run(
    run_definition,
    invocation,
    [definition],
    [artifact],
    manifest,
    receipt,
    [snapshot],
    [],
    authoring,
    [],
    65536,
    4096,
    32,
  ).unwrap()
  let codec_cid = native_payload_cid(token + "-codec")
  let payload_request = @payload.prepare_publication_payload_request(
    store_authority_cid,
    native_payload_cid(token + "-payload-attempt"),
    native_payload_cid(token + "-material"),
    @publication.publication_contract_identity(definition),
    logical_cid,
    schema_cid,
    @publication.publication_contract_identity(ordering),
    codec_cid,
    64L,
    1L,
  ).unwrap()
  let writer = store.begin_payload(payload_request).unwrap()
  writer.append(@utf8.encode(row_wire)).unwrap()
  let payload = writer.seal().unwrap()
  let binding = @publication.issue_durable_result_binding(
    run_definition,
    definition,
    invocation,
    artifact,
    ordering,
    retention,
    codec_cid,
    ["value"],
    schema_wire,
    payload.material_generation_cid,
    store_authority_cid,
    1,
    payload.generation.size.to_int(),
    payload.physical_digest[7:].to_owned(),
    65536,
    4096,
    32,
  ).unwrap()
  let request = @publication.issue_publication_request(
    run_definition,
    [definition],
    "namespace_id",
    authority_scope_cid,
    native_payload_cid(token + "-publication-policy"),
    native_payload_cid(token + "-publication-target"),
    "2026-09-20T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let attempt = @publication.issue_publication_attempt(
    request,
    run_definition,
    token + "-publication-attempt",
    native_payload_cid(token + "-fence"),
    None,
    "2026-09-20T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let index = @publication.issue_public_index_entry(
    run_definition,
    invocation,
    manifest,
    receipt,
    captured_run,
    [binding],
    request,
    attempt,
    "2026-09-20T00:00:02.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  {
    run_definition,
    invocation,
    definitions: [definition],
    artifacts: [artifact],
    derivations: [derivation],
    orderings: [ordering],
    retentions: [retention],
    bindings: [binding],
    manifest,
    receipt,
    captured_run,
    request,
    attempt,
    index,
    authority_scope_cid,
    material_generation_cid: payload.material_generation_cid,
    schema_wire,
  }
}

///|
fn commit_native_fixture(
  store : Store,
  fixture : NativePublicationCommitFixture,
) -> Result[NativePublicationCommit, NativePublicationStoreIssue] {
  store.commit_publication(
    fixture.run_definition,
    fixture.invocation,
    fixture.definitions,
    fixture.artifacts,
    fixture.derivations,
    fixture.orderings,
    fixture.retentions,
    fixture.bindings,
    [fixture.schema_wire],
    fixture.manifest,
    fixture.receipt,
    fixture.captured_run,
    fixture.request,
    fixture.attempt,
    fixture.index,
    65536,
    4096,
    32,
  )
}

///|
test "native publication commit is unique durable and restart-visible" {
  guard native_payload_fixture("publication-commit", 512L)
    is Some((store, authority, library)) else {
    return
  }
  let token = "publication-commit-" + @env.now().to_string()
  let fixture = native_commit_fixture(store, authority, token)
  let binding_read = @publication.project_durable_result_binding_read(
    fixture.bindings[0],
  ).unwrap()
  assert_true(
    store.read_result_schema(binding_read.result_schema_cid)
    is Err(Database(@sqlite.NotFound)),
  )
  assert_true(
    store
    .inspect_committed_publication(
      "namespace_id",
      fixture.authority_scope_cid,
      @publication.publication_contract_identity(fixture.run_definition),
      65536,
      4096,
      32,
    )
    .unwrap()
    is None,
  )
  assert_true(
    store.commit_publication(
      fixture.run_definition,
      fixture.invocation,
      fixture.definitions,
      fixture.artifacts,
      fixture.derivations,
      fixture.orderings,
      fixture.retentions,
      [],
      [],
      fixture.manifest,
      fixture.receipt,
      fixture.captured_run,
      fixture.request,
      fixture.attempt,
      fixture.index,
      65536,
      4096,
      32,
    )
    is Err(PublicationCommit(_)),
  )
  assert_true(
    store
    .inspect_committed_publication(
      "namespace_id",
      fixture.authority_scope_cid,
      @publication.publication_contract_identity(fixture.run_definition),
      65536,
      4096,
      32,
    )
    .unwrap()
    is None,
  )
  assert_true(
    store.commit_publication(
      fixture.run_definition,
      fixture.invocation,
      fixture.definitions,
      fixture.artifacts,
      fixture.derivations,
      fixture.orderings,
      fixture.retentions,
      fixture.bindings,
      ["{\"other\":{\"nullable\":false,\"type\":\"integer\"}}"],
      fixture.manifest,
      fixture.receipt,
      fixture.captured_run,
      fixture.request,
      fixture.attempt,
      fixture.index,
      65536,
      4096,
      32,
    )
    is Err(DeliveryIssuance(_)),
  )
  assert_true(
    store.read_result_schema(binding_read.result_schema_cid)
    is Err(Database(@sqlite.NotFound)),
  )
  let committed = commit_native_fixture(store, fixture).unwrap()
  assert_true(committed.committed)
  assert_false(committed.idempotent)
  let retry = commit_native_fixture(store, fixture).unwrap()
  assert_false(retry.committed)
  assert_true(retry.idempotent)
  let competing_attempt = @publication.issue_publication_attempt(
    fixture.request,
    fixture.run_definition,
    token + "-competing-attempt",
    native_payload_cid(token + "-competing-fence"),
    None,
    "2026-09-20T00:00:03.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let competing_index = @publication.issue_public_index_entry(
    fixture.run_definition,
    fixture.invocation,
    fixture.manifest,
    fixture.receipt,
    fixture.captured_run,
    fixture.bindings,
    fixture.request,
    competing_attempt,
    "2026-09-20T00:00:04.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    store.commit_publication(
      fixture.run_definition,
      fixture.invocation,
      fixture.definitions,
      fixture.artifacts,
      fixture.derivations,
      fixture.orderings,
      fixture.retentions,
      fixture.bindings,
      [fixture.schema_wire],
      fixture.manifest,
      fixture.receipt,
      fixture.captured_run,
      fixture.request,
      competing_attempt,
      competing_index,
      65536,
      4096,
      32,
    )
    is Err(PublicationCommitConflict),
  )
  assert_true(store.close().unwrap())
  let reopened = open_store(
    library,
    @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap(),
    authority,
    512L,
    8L,
    65536L,
  ).unwrap()
  let visible = reopened
    .inspect_committed_publication(
      "namespace_id",
      fixture.authority_scope_cid,
      @publication.publication_contract_identity(fixture.run_definition),
      65536,
      4096,
      32,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    @publication.publication_contract_identity(visible),
    committed.public_index_entry_cid,
  )
  assert_eq(
    reopened.read_result_schema(binding_read.result_schema_cid).unwrap(),
    fixture.schema_wire,
  )
  let resolved = reopened
    .resolve_committed_result(
      "namespace_id",
      fixture.authority_scope_cid,
      @publication.publication_contract_identity(fixture.run_definition),
      "answer",
      65536,
      4096,
      32,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    resolved.read.material_generation_cid,
    fixture.material_generation_cid,
  )
  assert_eq(resolved.read.result_schema_cid, binding_read.result_schema_cid)
  assert_eq(
    @publication.publication_contract_identity(resolved.result_manifest),
    @publication.publication_contract_identity(fixture.manifest),
  )
  assert_true(
    reopened.resolve_committed_result(
      "namespace_id",
      fixture.authority_scope_cid,
      @publication.publication_contract_identity(fixture.run_definition),
      "missing",
      65536,
      4096,
      32,
    )
    is Err(
      DeliveryIssuance(@publication.DeliveryIssuanceUnknownResult("missing"))
    ),
  )
  let stored_manifest = reopened
    .read_publication_contract(
      "result_manifest",
      @publication.publication_contract_identity(fixture.manifest),
    )
    .unwrap()
  assert_eq(
    @publication.publication_contract_identity(stored_manifest),
    @publication.publication_contract_identity(fixture.manifest),
  )
  assert_true(reopened.close().unwrap())
}

///|
test "native trusted clock remains monotonic across restart" {
  guard native_payload_fixture("trusted-clock", 64L)
    is Some((store, authority, library)) else {
    return
  }
  let clock = native_payload_cid("trusted-clock-contract")
  assert_eq(
    store.observe_trusted_clock(clock, "2026-09-20T01:00:00.000Z").unwrap(),
    "2026-09-20T01:00:00.000Z",
  )
  assert_true(
    store.observe_trusted_clock(clock, "2026-09-20T00:59:59.999Z")
    is Err(ClockRegression),
  )
  assert_eq(
    store.observe_trusted_clock(clock, "2026-09-20T01:00:00.001Z").unwrap(),
    "2026-09-20T01:00:00.001Z",
  )
  assert_true(store.close().unwrap())
  let reopened = open_store(
    library,
    @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap(),
    authority,
    64L,
    8L,
    65536L,
  ).unwrap()
  assert_true(
    reopened.observe_trusted_clock(clock, "2026-09-20T01:00:00.000Z")
    is Err(ClockRegression),
  )
  assert_eq(
    reopened.observe_trusted_clock(clock, "2026-09-20T01:00:00.002Z").unwrap(),
    "2026-09-20T01:00:00.002Z",
  )
  assert_true(reopened.close().unwrap())
}

///|
test "native formal delivery durably binds attempt receipt and success" {
  guard native_payload_fixture("formal-delivery", 256L)
    is Some((store, authority, library)) else {
    return
  }
  let token = "formal-delivery-" + @env.now().to_string()
  let fixture = native_commit_fixture(store, authority, token)
  ignore(commit_native_fixture(store, fixture).unwrap())
  let schema_wire = fixture.schema_wire
  let retention = fixture.retentions[0]
  let manifest = fixture.manifest
  let binding = fixture.bindings[0]
  let index = fixture.index
  let info = store.inspect_payload(fixture.material_generation_cid).unwrap()
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
      ["value"],
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
  assert_eq(@utf8.decode_lossy(Bytes::from_array(delivered)), "{\"value\":7}\n")
  assert_eq(success.confirmed_bytes, 12L)
  assert_eq(success.delivered_sha256, @sha.text_hex("{\"value\":7}\n").unwrap())
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
      ["value"],
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
      ["value"],
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
  let durable_schema_wire = reopened
    .read_result_schema(info.result_schema_cid)
    .unwrap()
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
      durable_schema_wire,
      ["value"],
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

///|
/// The Store's own allocation steps, as begin_payload takes them, stopped as
/// a killed process would: records and files are left, the writer is never
/// cancelled. `stage` names the stop: "recorded" before the area is created,
/// "allocated" after the file exists, "owned" after its ownership is durable.
fn native_stopped_allocation(
  store : Store,
  request : @payload.PublicationPayloadRequest,
  stage : String,
) -> (String, @filesystem.Writer?) {
  let key = record_key(request)
  let record = @payload.prepare_publication_payload_record(request)
  ignore(
    store.database
    .insert(
      "publication_payload",
      key,
      @utf8.encode(
        @payload.publication_payload_record_durable_json(record).unwrap(),
      ),
    )
    .unwrap(),
  )
  ignore(
    store.database
    .reserve_capacity(
      "publication_payload",
      key,
      @payload.publication_payload_request_max_bytes(request),
      1L,
      store.capacity_bytes,
      store.max_objects,
    )
    .unwrap(),
  )
  let reserved = persist_transition(
    store,
    @payload.prepare_publication_payload_reserved(record).unwrap(),
  ).unwrap()
  let writing = persist_transition(
    store,
    @payload.prepare_publication_payload_writing(reserved).unwrap(),
  ).unwrap()
  let name = allocation_name(
    request,
    next_allocation_ordinal(store, request).unwrap(),
  )
  record_allocation(store, key, { name, identity: None, }).unwrap()
  if stage == "recorded" {
    return (name, None)
  }
  let identity = store.root.create_directory(name).unwrap()
  record_allocation(store, key, { name, identity: Some(identity), }).unwrap()
  let area = store.root.open_child(name).unwrap()
  let stopped = area.create_writer(ALLOCATION_FILE, 32L).unwrap()
  stopped.append(b"partial").unwrap()
  if stage == "owned" {
    ignore(
      persist_transition(
        store,
        @payload.prepare_publication_payload_owned(
          writing,
          payload_ownership(stopped.ownership()),
        ).unwrap(),
      ).unwrap(),
    )
  }
  (name, Some(stopped))
}

///|
test "native publication recovery reclaims an allocation stopped before or after its ownership is durable and leaves foreign staging" {
  guard native_payload_fixture("allocation-window", 4096L)
    is Some((store, authority, _)) else {
    return
  }
  // The root's capacity namespace is shared with the other tests' Stores,
  // some of which keep a sealed payload: only this test's delta is checked.
  let base = store.capacity_usage().unwrap().reserved_bytes
  for stage in ["allocated", "owned"] {
    let request = native_payload_request(
      authority,
      "allocation-window-" + stage + "-" + @env.now().to_string(),
      32L,
    )
    // A foreign file at the public staging name that no record owns.
    let public_name = @payload.publication_payload_staging_name(request)
    let foreign = store.root.create_writer(public_name, 32L).unwrap()
    foreign.append(b"foreign").unwrap()
    let foreign_before = store.root
      .inspect_generation(public_name)
      .unwrap()
      .unwrap()
    let (name, stopped) = native_stopped_allocation(store, request, stage)
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, base + 32L)
    assert_true(store.root.inspect_directory(name).unwrap() is Some(_))
    // Recovery, as the next Store open runs it: the area the Store proved
    // it created goes with its file, the capacity is released, and the
    // foreign file stays.
    let recovered = store.recover().unwrap()
    assert_eq(recovered.reclaimed, 1)
    assert_eq(store.root.inspect_directory(name).unwrap(), None)
    assert_eq(
      store.root.inspect_generation(public_name).unwrap(),
      Some(foreign_before),
    )
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, base)
    // The same request is reclaimed once; a second recovery changes nothing.
    assert_eq(store.recover().unwrap().reclaimed, 0)
    assert_eq(
      store.root.inspect_generation(public_name).unwrap(),
      Some(foreign_before),
    )
    ignore(stopped)
    foreign.cancel().unwrap()
  }
  assert_true(store.close().unwrap())
}

///|
test "native publication allocation preparation failures reclaim the acquired area" {
  guard native_payload_fixture("allocation-failure", 4096L)
    is Some((store, authority, _)) else {
    return
  }
  let base = store.capacity_usage().unwrap()
  for step in ["identity", "open", "writer"] {
    let request = native_payload_request(
      authority,
      "allocation-failure-" + step + "-" + @env.now().to_string(),
      32L,
    )
    let name = allocation_name(request, 1L)
    let issue = Filesystem(@filesystem.WriterCreate("injected-" + step))
    let injected = Ref(false)
    store.allocation_failure.val = Some(fn(actual) {
      if actual == step && !injected.val {
        injected.val = true
        Some(issue)
      } else {
        None
      }
    })
    guard store.begin_payload(request) is Err(actual) else {
      fail("allocation preparation fault was not injected")
    }
    assert_true(
      actual is Filesystem(@filesystem.WriterCreate(message)) &&
      message == "injected-" + step,
    )
    store.allocation_failure.val = None
    assert_eq(store.root.inspect_directory(name).unwrap(), None)
    let usage = store.capacity_usage().unwrap()
    assert_eq(usage.reserved_bytes, base.reserved_bytes)
    assert_eq(usage.reserved_objects, base.reserved_objects)
    assert_eq(store.recover().unwrap().reclaimed, 0)
  }
  assert_true(store.close().unwrap())
}

///|
test "native publication nonempty allocation keeps capacity and does not delete unrelated files" {
  guard native_payload_fixture("allocation-not-empty", 4096L)
    is Some((store, authority, _)) else {
    return
  }
  let base = store.capacity_usage().unwrap()
  let request = native_payload_request(
    authority,
    "allocation-not-empty-" + @env.now().to_string(),
    32L,
  )
  let name = allocation_name(request, 1L)
  let unrelated : Ref[@filesystem.Writer?] = Ref(None)
  store.allocation_failure.val = Some(fn(step) {
    if step == "writer" {
      let file = store.root
        .open_child(name)
        .unwrap()
        .create_writer("unrelated", 16L)
        .unwrap()
      file.append(b"foreign").unwrap()
      unrelated.val = Some(file)
      Some(Filesystem(@filesystem.WriterCreate("injected-writer")))
    } else {
      None
    }
  })
  assert_true(store.begin_payload(request) is Err(CleanupPending))
  store.allocation_failure.val = None
  let identity = store.root.inspect_directory(name).unwrap()
  let before = store.root
    .open_child(name)
    .unwrap()
    .inspect_generation("unrelated")
    .unwrap()
  let cleanup = store.acquire_payload_cleanup(request).unwrap()
  assert_true(cleanup.retry() is Err(CleanupPending))
  assert_true(cleanup.pending())
  assert_eq(store.root.inspect_directory(name).unwrap(), identity)
  assert_eq(
    store.root
    .open_child(name)
    .unwrap()
    .inspect_generation("unrelated")
    .unwrap(),
    before,
  )
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    base.reserved_bytes + 32L,
  )
  unrelated.val.unwrap().cancel().unwrap()
  assert_true(cleanup.retry().unwrap())
  assert_false(cleanup.retry().unwrap())
  assert_eq(store.root.inspect_directory(name).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, base.reserved_bytes)
  assert_true(store.close().unwrap())
}

///|
test "native publication allocation creation sync failure retains its exact cleanup owner" {
  guard native_payload_fixture("allocation-create-sync", 4096L)
    is Some((store, authority, _)) else {
    return
  }
  let base = store.capacity_usage().unwrap()
  let request = native_payload_request(
    authority,
    "allocation-create-sync-" + @env.now().to_string(),
    32L,
  )
  let name = allocation_name(request, 1L)
  // Actual mkdir succeeds, but the first durability confirmation and the
  // cleanup's directory sync fail. This is not a simulated create result.
  test_fail_root_sync(store.root, 2)
  assert_true(store.begin_payload(request) is Err(CleanupPending))
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    base.reserved_bytes + 32L,
  )
  let cleanup = store.acquire_payload_cleanup(request).unwrap()
  assert_true(cleanup.pending())
  assert_true(cleanup.retry().unwrap())
  assert_false(cleanup.pending())
  assert_false(cleanup.retry().unwrap())
  assert_eq(store.root.inspect_directory(name).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, base.reserved_bytes)
  assert_true(store.close().unwrap())
}

///|
#borrow(root)
extern "C" fn test_fail_created_directory_inspect(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_created_directory_inspect"

///|
test "native publication allocation without confirmed identity stays pending" {
  guard native_payload_fixture("allocation-inspect", 4096L)
    is Some((store, authority, _)) else {
    return
  }
  let base = store.capacity_usage().unwrap().reserved_bytes
  let request = native_payload_request(
    authority,
    "allocation-inspect-" + @env.now().to_string(),
    32L,
  )
  let name = allocation_name(request, 1L)
  test_fail_created_directory_inspect(store.root, 1)
  assert_true(store.begin_payload(request) is Err(CleanupPending))
  let directory = store.root.inspect_directory(name).unwrap().unwrap()
  assert_true(
    recorded_allocation(store, request).unwrap() is Some({ identity: None, .. }),
  )
  let cleanup = store.acquire_payload_cleanup(request).unwrap()
  assert_true(cleanup.retry() is Err(RecoveryRequired))
  assert_true(cleanup.pending())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, base + 32L)
  assert_eq(store.root.inspect_directory(name).unwrap(), Some(directory))
  // Test-fixture disposal uses the separately captured identity, not a
  // product repair API or an inferred ownership record.
  assert_true(store.root.remove_directory(name, directory).unwrap())
  assert_true(cleanup.retry().unwrap())
  assert_false(cleanup.retry().unwrap())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, base)
  assert_true(store.close().unwrap())
}

///|
test "native publication failed allocation ownership keeps cleanup and capacity until retry" {
  guard native_payload_fixture("allocation-owner-retry", 4096L)
    is Some((store, authority, _)) else {
    return
  }
  let base = store.capacity_usage().unwrap()
  let request = native_payload_request(
    authority,
    "allocation-owner-retry-" + @env.now().to_string(),
    32L,
  )
  let key = record_key(request)
  let name = allocation_name(request, 1L)
  store.allocation_failure.val = Some(fn(step) {
    if step == "identity" {
      Some(Database(@sqlite.DatabaseClosed))
    } else {
      None
    }
  })
  assert_true(store.begin_payload(request) is Err(CleanupPending))
  let identity = store.root.inspect_directory(name).unwrap().unwrap()
  assert_true(
    store.pending_allocations.get(key) is Some({ identity: Some(owned), .. }) &&
    owned == identity,
  )
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    base.reserved_bytes + 32L,
  )
  assert_true(store.begin_payload(request) is Err(RecoveryRequired))
  let cleanup = store.acquire_payload_cleanup(request).unwrap()
  assert_true(cleanup.retry() is Err(Database(@sqlite.DatabaseClosed)))
  assert_true(cleanup.pending())
  assert_true(store.close() is Err(Database(@sqlite.DatabaseClosed)))
  assert_eq(store.root.inspect_directory(name).unwrap(), Some(identity))
  assert_true(
    @payload.publication_payload_record_state(load_record(store, key).unwrap()) !=
    @payload.Reclaimed,
  )
  store.allocation_failure.val = None
  assert_true(cleanup.retry().unwrap())
  assert_false(cleanup.pending())
  assert_false(cleanup.retry().unwrap())
  assert_false(store.pending_allocations.contains(key))
  assert_eq(store.root.inspect_directory(name).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, base.reserved_bytes)
  assert_true(store.close().unwrap())
  assert_false(store.close().unwrap())
}

///|
test "native publication allocation preparation cleanup survives sync failure and restart" {
  guard native_payload_fixture("allocation-failure-restart", 4096L)
    is Some((initial, authority, library)) else {
    return
  }
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let base = initial.capacity_usage().unwrap()
  let current = Ref(initial)
  for step in ["identity", "open", "writer"] {
    let store = current.val
    let request = native_payload_request(
      authority,
      "allocation-restart-" + step + "-" + @env.now().to_string(),
      32L,
    )
    let name = allocation_name(request, 1L)
    let foreign_name = @payload.publication_payload_staging_name(request)
    let foreign = store.root.create_writer(foreign_name, 16L).unwrap()
    foreign.append(b"foreign").unwrap()
    let before = store.root.inspect_generation(foreign_name).unwrap()
    let injected = Ref(false)
    store.allocation_failure.val = Some(fn(actual) {
      if actual == step && !injected.val {
        injected.val = true
        test_fail_root_sync(store.root, 1)
        Some(Filesystem(@filesystem.WriterCreate("injected-" + step)))
      } else {
        None
      }
    })
    assert_true(store.begin_payload(request) is Err(CleanupPending))
    assert_eq(
      store.capacity_usage().unwrap().reserved_bytes,
      base.reserved_bytes + 32L,
    )
    assert_true(
      @payload.publication_payload_record_state(
        load_record(store, record_key(request)).unwrap(),
      )
      is @payload.Reclaiming,
    )
    // Simulate process death: no Store cleanup or mutation of its payload records.
    store.database.close()
    assert_true(store.lock.close())
    let reopened = open_store(library, root, authority, 4096L, 8L, 65536L).unwrap()
    assert_eq(reopened.recover().unwrap().reclaimed, 1)
    assert_eq(reopened.root.inspect_directory(name).unwrap(), None)
    assert_eq(reopened.root.inspect_generation(foreign_name).unwrap(), before)
    assert_eq(
      reopened.capacity_usage().unwrap().reserved_bytes,
      base.reserved_bytes,
    )
    assert_eq(
      reopened.capacity_usage().unwrap().reserved_objects,
      base.reserved_objects,
    )
    assert_eq(reopened.recover().unwrap().reclaimed, 0)
    foreign.cancel().unwrap()
    current.val = reopened
  }
  assert_true(current.val.close().unwrap())
}

///|
test "native publication recovery never takes what stands at an allocation name it did not create" {
  guard native_payload_fixture("allocation-foreign", 4096L)
    is Some((initial, authority, library)) else {
    return
  }
  let current = Ref(initial)
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let store = current.val
  let base = store.capacity_usage().unwrap().reserved_bytes
  // First a foreign file at the name; then a foreign directory holding a
  // file. In both, the Store recorded the name and stopped before creating
  // the area (or its creation conflicted and the stop came before the
  // failure was made durable): ownership is ambiguous after a stop. The
  // record and capacity remain pending; nothing at the name is touched.
  for kind in ["file", "directory"] {
    let store = current.val
    let request = native_payload_request(
      authority,
      "allocation-foreign-" + kind + "-" + @env.now().to_string(),
      32L,
    )
    let name = allocation_name(request, 1L)
    let foreign_file = if kind == "file" {
      store.root.create_writer(name, 32L).unwrap()
    } else {
      ignore(store.root.create_directory(name).unwrap())
      store.root
      .open_child(name)
      .unwrap()
      .create_writer(ALLOCATION_FILE, 32L)
      .unwrap()
    }
    foreign_file.append(b"foreign").unwrap()
    let before = if kind == "file" {
      store.root.inspect_generation(name).unwrap().unwrap()
    } else {
      store.root
      .open_child(name)
      .unwrap()
      .inspect_generation(ALLOCATION_FILE)
      .unwrap()
      .unwrap()
    }
    let (recorded, _) = native_stopped_allocation(store, request, "recorded")
    assert_eq(recorded, name)
    // The Store's own creation at that name is a conflict, never a claim.
    assert_true(store.root.create_directory(name) is Err(@filesystem.Conflict))
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, base + 32L)
    assert_true(store.recover() is Err(RecoveryRequired))
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, base + 32L)
    assert_true(store.begin_payload(request) is Err(RecoveryRequired))
    let cleanup = store.acquire_payload_cleanup(request).unwrap()
    assert_true(cleanup.retry() is Err(RecoveryRequired))
    assert_true(cleanup.pending())
    assert_true(store.close() is Err(RecoveryRequired))
    assert_eq(next_allocation_ordinal(store, request).unwrap(), 2L)
    let durable_before = store.database
      .read("publication_payload", record_key(request))
      .unwrap()
    assert_true(
      @payload.publication_payload_record_state(
        load_record(store, record_key(request)).unwrap(),
      )
      is @payload.Reclaiming,
    )
    // Simulate losing the live process's knowledge, then re-open.
    store.database.close()
    assert_true(store.lock.close())
    let reopened = open_store(library, root, authority, 4096L, 8L, 65536L).unwrap()
    assert_true(reopened.recover() is Err(RecoveryRequired))
    assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, base + 32L)
    assert_eq(
      reopened.database
      .read("publication_payload", record_key(request))
      .unwrap().body,
      durable_before.body,
    )
    assert_true(reopened.begin_payload(request) is Err(RecoveryRequired))
    let after = if kind == "file" {
      store.root.inspect_generation(name).unwrap().unwrap()
    } else {
      store.root
      .open_child(name)
      .unwrap()
      .inspect_generation(ALLOCATION_FILE)
      .unwrap()
      .unwrap()
    }
    assert_eq(after, before)
    // The next allocation of the same request never returns to that name.
    assert_eq(next_allocation_ordinal(reopened, request).unwrap(), 2L)
    foreign_file.cancel().unwrap()
    if kind == "directory" {
      let identity = reopened.root.inspect_directory(name).unwrap().unwrap()
      assert_true(reopened.root.remove_directory(name, identity).unwrap())
    }
    // Only this test's separate, known foreign owner removed its entry.
    // Absence is then synchronized by the existing reclaim owner.
    let retry = reopened.acquire_payload_cleanup(request).unwrap()
    assert_true(retry.retry().unwrap())
    assert_false(retry.retry().unwrap())
    assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, base)
    current.val = reopened
  }
  assert_true(current.val.close().unwrap())
}
