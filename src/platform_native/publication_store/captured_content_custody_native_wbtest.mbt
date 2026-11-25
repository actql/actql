///|
fn[T, E] Result::captured_content_stage(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
fn native_content_store_fixture(
  label : String,
  capacity : Int64,
  library : @sqlite.Library,
  diagnostic_ceiling? : Int? = None,
) -> (Store, String, String) raise {
  // The ordinary Core harness already owns a fresh SQLite namespace. Use it
  // only as this fixture's parent; never activate a global optional Store root
  // for unrelated packages. Explicit focused fixture selection stays first.
  let root = match @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") {
    Some(root) => root
    None =>
      match @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") {
        Some(root) => root
        None => fail("Missing explicit Native Content Store fixture")
      }
  }
  let token = label + "-" + @env.now().to_string()
  let authority = native_payload_cid(token + "-authority")
  let parent = @filesystem.open_root(root).captured_content_stage(
    "Content parent Root open",
  )
  parent
  .create_directory(token)
  .captured_content_stage("Content fresh namespace")
  |> ignore
  parent.close().captured_content_stage("Content parent Root close")
  let selected = root + "/" + token
  let store = match diagnostic_ceiling {
    None =>
      open_store(library, selected, authority, capacity, 8L, 65536L).captured_content_stage(
        "Content Store open",
      )
    Some(limit) =>
      open_store_with_custody(
        library,
        selected,
        authority,
        capacity,
        8L,
        65536L,
        diagnostic_ceiling=Some(limit),
      ).captured_content_stage("Content bounded Store open")
  }
  (store, authority, selected)
}

///|
test "Native bounded Content custody quotes its original constructors before the Store child" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = @sqlite.load_library(path).captured_content_stage(
    "Content original library",
  )
  native_content_funded_constructor_case(library)
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
fn native_content_funded_constructor_case(
  library : @sqlite.Library,
) -> Unit raise {
  let (unbounded, _, _) = native_content_store_fixture(
    "unbounded-quote", 16L, library,
  )
  assert_true(
    unbounded.captured_content_custody_construction_inventory(2) is None,
  )
  assert_true(
    unbounded.close().captured_content_stage("unbounded Store closed"),
  )
  let (store, authority, _) = native_content_store_fixture(
    "bounded-construction",
    16L,
    library,
    diagnostic_ceiling=Some(128),
  )
  assert_eq(store.root.diagnostic_ceiling(), Some(128))
  assert_true(store.captured_content_custody_construction_inventory(0) is None)
  assert_true(
    store.captured_content_custody_construction_inventory(1048577) is None,
  )
  let small = store.captured_content_custody_construction_inventory(2).unwrap()
  let larger = store.captured_content_custody_construction_inventory(3).unwrap()
  // Exactly the old C and returned chunk storage changes; quoted controls,
  // records, shared parser/Map inventories and original Root stay identical.
  assert_eq(larger.record_headers, small.record_headers)
  assert_eq(larger.reference_slots, small.reference_slots)
  assert_eq(larger.scalar_words, small.scalar_words)
  assert_eq(larger.owned_utf16_units, small.owned_utf16_units)
  assert_eq(larger.owned_wire_bytes - small.owned_wire_bytes, 2L)
  let bytes = b"e\xcc\x81\r\n\xf0\x9f\x8c\xb1"
  let original = native_content_candidate(authority, bytes)
  let child = store
    .prepare_captured_content_custody(
      original,
      native_payload_cid("bounded-construction-holding"),
    )
    .captured_content_stage("bounded original custody")
  child.persist(bytes).captured_content_stage("bounded original persist")
  child.confirm(2).captured_content_stage("bounded original verify")
  assert_true(child.matches_confirmed(original))
  assert_true(
    child.retry_cleanup().captured_content_stage("bounded original cleanup"),
  )
  assert_true(store.close().captured_content_stage("bounded Store close"))
  assert_true(store.captured_content_custody_construction_inventory(2) is None)
}

///|
// Explicit Common binding DATA for this physical Store component, not an
// Account, Source request, Run, installed Host or normal constructor recipe.
fn native_content_binding(
  authority : String,
) -> @publication.GeneratedContentBinding {
  {
    content_store_id: "native-store-component",
    content_store_cid: authority,
    workspace_scope_cid: native_payload_cid("content-workspace"),
    storage_scope: "workspace",
    retention_class: "component",
    expires_at: None,
    availability_evidence_cid: native_payload_cid("content-availability"),
    effective_data_policy_cid: native_payload_cid("content-data-policy"),
    data_classification: "internal",
    issuer_contract_cid: native_payload_cid("content-issuer"),
    capture_authority_cid: native_payload_cid("content-read-subject"),
  }
}

///|
fn native_content_candidate(
  authority : String,
  bytes : Bytes,
) -> @publication.CapturedContentReference raise {
  @publication.prepare_captured_content_reference(
    native_content_binding(authority),
    "text/plain",
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
    { max_bytes: 4096, max_nodes: 100, max_depth: 8, max_text_units: 4096, },
  ).captured_content_stage("Content stage 1")
}

///|
test "Native captured Content Store persists exact bytes verifies original custody and restores without another holding" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("Missing explicit Native Content SQLite library")
  }
  let library = @sqlite.load_library(path).captured_content_stage(
    "Content original library",
  )
  native_content_physical_case_1(library)
  // This stock Library cannot issue the selected-component cleanup ACK.
  // Store/Writer/Reader close assertions above cover their original owners.
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
fn native_generated_jsonl(
  authority : String,
  reference_limits : @admitted.ReferenceLimits,
) -> (@publication.GeneratedContentReference, NativeGeneratedContentOutput) raise {
  let (encoder, rows) = generated_jsonl_test_input()
  let output = start_native_generated_content_output(encoder).captured_content_stage(
    "retain the fixed Native encoder backing",
  )
  assert_true(output.advance(64).0 is Ok(true))
  for value in rows {
    @publication.start_content_byte_row(encoder, _ => Some(value)).captured_content_stage(
      "start the original row",
    )
    let mut done = false
    for _ in 0..<32 {
      let (advance, work) = output.advance(7)
      assert_true(work > 0 && work <= 7)
      done = advance.captured_content_stage("advance the same Native output")
      if done {
        break
      }
    }
    assert_true(done)
  }
  let complete = @publication.finish_content_bytes(encoder).captured_content_stage(
    "finish the original encoder",
  )
  assert_eq((complete.row_count, complete.size_bytes), (2, 18))
  let candidate = @publication.prepare_generated_content_reference(
    encoder,
    native_content_binding(authority),
    reference_limits,
  ).captured_content_stage("construct the Common generated candidate")
  (candidate, output)
}

///|
test "Native generated Content issues and reopens only under its verified Store original" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = @sqlite.load_library(path).captured_content_stage(
    "generated Content library",
  )
  let (store, authority, store_path) = native_content_store_fixture(
    "generated-content-original",
    18L,
    library,
    diagnostic_ceiling=Some(512),
  )
  let limits : @admitted.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let (candidate, output) = native_generated_jsonl(authority, limits)
  let (equal_candidate, equal_output) = native_generated_jsonl(
    authority, limits,
  )
  let (foreign, _) = native_generated_jsonl(
    native_payload_cid("foreign-generated-store"),
    limits,
  )
  let holding = native_payload_cid("generated-content-original-holding")
  let bytes = b"{\"id\":1}\n{\"id\":2}\n"
  assert_eq(output.backing.length(), 64)
  assert_eq(output.written, bytes.length())
  assert_true(
    output.backing
    .unsafe_reinterpret_as_bytes()
    .view(end=18)
    .equal_to_bytes(bytes),
  )
  assert_eq(
    @publication.generated_content_reference_storage(candidate).2,
    "sha256:c63f6dd68b68601e7315ea40d28bc34e55379e4fa65f82b1d32228429aeafcde",
  )
  assert_true(
    store.generated_content_custody_construction_inventory(4, candidate)
    is Some(_),
  )
  assert_true(
    store.generated_content_custody_construction_inventory(4, foreign) is None,
  )
  assert_true(
    store.prepare_generated_content_custody(foreign, holding)
    is Err(StateCollision),
  )
  let custody = store
    .prepare_generated_content_custody(candidate, holding)
    .captured_content_stage("retain the exact generated candidate")
  assert_true(custody.matches_generated_selection(store, candidate, holding))
  assert_false(
    custody.matches_generated_selection(store, equal_candidate, holding),
  )
  assert_false(
    custody.matches_generated_selection(
      store,
      candidate,
      native_payload_cid("foreign-holding"),
    ),
  )
  let wire = @publication.generated_content_reference_wire(candidate)
  let authorized = Ref(true)
  let issuer = @admitted.bind_reference_issuer(
    (_, received) => {
      received == wire && custody.matches_generated_confirmed(candidate)
    },
    _ => authorized.val,
  )
  assert_true(
    @publication.issue_generated_content_reference(candidate, issuer, limits)
    is Err(_),
  )
  assert_true(custody.persist(bytes) is Err(RecoveryRequired))
  assert_true(
    custody.persist_generated_output(equal_output) is Err(StateCollision),
  )
  output.written -= 1
  assert_true(custody.persist_generated_output(output) is Err(DigestMismatch))
  output.written += 1
  let first = output.backing[0]
  output.backing[0] = b'x'
  assert_true(custody.persist_generated_output(output) is Err(DigestMismatch))
  output.backing[0] = first
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 0L)
  custody
  .persist_generated_output(output)
  .captured_content_stage("persist only the original generated prefix")
  assert_false(custody.matches_generated_confirmed(candidate))
  assert_true(store.close() is Err(CleanupPending))
  custody
  .confirm(4)
  .captured_content_stage("verify the actual stored generation")
  assert_true(custody.matches_generated_confirmed(candidate))
  assert_false(custody.matches_generated_confirmed(equal_candidate))
  let issued = @publication.issue_generated_content_reference(
    candidate, issuer, limits,
  ).captured_content_stage("issue the original generated reference")
  guard issued.value is @admitted.Reference(reference) else {
    fail("generated content was not a typed reference")
  }
  let saved_wire = @admitted.reference_wire(reference)
  assert_eq(saved_wire, wire)
  authorized.val = false
  assert_true(
    @publication.issue_generated_content_reference(candidate, issuer, limits)
    is Err(_),
  )
  assert_true(
    custody
    .retry_cleanup()
    .captured_content_stage("close original generated custody"),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 18L)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 1L)
  assert_true(
    store.close().captured_content_stage("close original generated Store"),
  )
  assert_false(custody.matches_generated_confirmed(candidate))
  let reopened = open_existing_store_with_custody(
    library,
    store_path,
    authority,
    18L,
    8L,
    65536L,
    diagnostic_ceiling=Some(512),
  ).captured_content_stage("reopen only the existing generated Store")
  let binding = native_content_binding(authority)
  assert_true(
    @publication.prepare_stored_generated_content_reference(
      saved_wire,
      {
        ..binding,
        workspace_scope_cid: native_payload_cid("unrelated-workspace"),
      },
      limits,
    )
    is Err(_),
  )
  let saved = @publication.prepare_stored_generated_content_reference(
    saved_wire, binding, limits,
  ).captured_content_stage("readmit the saved canonical reference")
  let equal_saved = @publication.prepare_stored_generated_content_reference(
    saved_wire, binding, limits,
  ).captured_content_stage("independent saved reference carrier")
  assert_true(
    reopened.saved_generated_content_custody_construction_inventory(4, saved)
    is Some(_),
  )
  let readback = reopened
    .prepare_saved_generated_content_custody(saved, holding)
    .captured_content_stage("retain the original saved holding")
  let restored_issuer = @admitted.bind_reference_issuer(
    (_, received) => {
      received == saved_wire &&
      readback.matches_saved_generated_confirmed(saved)
    },
    _ => authorized.val,
  )
  authorized.val = true
  assert_true(readback.persist(bytes) is Err(RecoveryRequired))
  assert_true(
    @publication.issue_stored_generated_content_reference(
      saved, restored_issuer, limits,
    )
    is Err(_),
  )
  readback
  .restore()
  .captured_content_stage("restore original record without a writer")
  assert_true(readback.writer is None)
  assert_false(readback.matches_saved_generated_confirmed(saved))
  readback
  .confirm(3)
  .captured_content_stage("verify saved original file generation")
  assert_true(readback.matches_saved_generated_confirmed(saved))
  assert_false(readback.matches_saved_generated_confirmed(equal_saved))
  let restored = @publication.issue_stored_generated_content_reference(
    saved, restored_issuer, limits,
  ).captured_content_stage("issue exact restored Content")
  guard restored.value is @admitted.Reference(saved_reference) else {
    fail("saved content was not a typed reference")
  }
  assert_eq(@admitted.reference_wire(saved_reference), saved_wire)
  assert_eq(
    @admitted.reference_identity_cid(saved_reference),
    @admitted.reference_identity_cid(reference),
  )
  assert_true(
    readback.retry_cleanup().captured_content_stage("close same saved reader"),
  )
  assert_eq(reopened.capacity_usage().unwrap().reserved_objects, 1L)
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, 18L)
  assert_true(
    reopened.close().captured_content_stage("close original reopened Store"),
  )
  assert_false(readback.matches_saved_generated_confirmed(saved))
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
fn native_content_physical_case_1(library : @sqlite.Library) -> Unit raise {
  let (store, authority, path) = native_content_store_fixture(
    "captured-content-original", 64L, library,
  )
  let bytes = b"e\xcc\x81\r\n\xf0\x9f\x8c\xb1"
  let original = native_content_candidate(authority, bytes)
  let holding = native_payload_cid("captured-content-original-holding")
  let custody = store
    .prepare_captured_content_custody(original, holding)
    .captured_content_stage("Content stage 3")
  assert_false(custody.matches_confirmed(original))
  assert_true(custody.persist(b"wrong") is Err(DigestMismatch))
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 4").reserved_objects,
    0L,
  )
  custody.persist(bytes).captured_content_stage("Content stage 5")
  assert_false(custody.matches_confirmed(original))
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 6").reserved_bytes,
    9L,
  )
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 7").reserved_objects,
    1L,
  )
  assert_true(store.close() is Err(CleanupPending))
  custody.confirm(2).captured_content_stage("Content stage 8")
  assert_true(custody.matches_confirmed(original))
  let equal_candidate = native_content_candidate(authority, bytes)
  assert_false(custody.matches_confirmed(equal_candidate))
  assert_true(custody.persist(bytes) is Err(RecoveryRequired))
  assert_true(custody.retry_cleanup().captured_content_stage("Content stage 9"))
  // I/O retirement preserves durable DATA; Source/Run currentness is still
  // independently necessary before its actual ReferenceIssuer may use it.
  assert_true(custody.matches_confirmed(original))
  assert_true(store.close().captured_content_stage("Content stage 10"))
  assert_false(custody.matches_confirmed(original))
  let reopened = open_existing_store(library, path, authority, 64L, 8L, 65536L).captured_content_stage(
    "Content stage 11",
  )
  let restored = reopened
    .prepare_captured_content_custody(equal_candidate, holding)
    .captured_content_stage("Content stage 12")
  restored.restore().captured_content_stage("Content stage 13")
  restored.confirm(3).captured_content_stage("Content stage 14")
  assert_true(restored.matches_confirmed(equal_candidate))
  assert_eq(
    reopened.capacity_usage().captured_content_stage("Content stage 15").reserved_bytes,
    9L,
  )
  assert_eq(
    reopened.capacity_usage().captured_content_stage("Content stage 16").reserved_objects,
    1L,
  )
  assert_true(
    restored.retry_cleanup().captured_content_stage("Content stage 17"),
  )
  assert_true(reopened.close().captured_content_stage("Content stage 18"))
}

///|
test "Native distinct equal Content candidates verify one sealed holding" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = @sqlite.load_library(path).captured_content_stage("library")
  let (store, authority, _) = native_content_store_fixture(
    "captured-content-equal-candidates", 6L, library,
  )
  let bytes = b"shared"
  let first = native_content_candidate(authority, bytes)
  let second = native_content_candidate(authority, bytes)
  assert_false(physical_equal(first, second))
  assert_eq(
    @publication.captured_content_reference_identity(first),
    @publication.captured_content_reference_identity(second),
  )
  let holding = native_payload_cid("captured-content-equal-candidates-holding")
  let original = store
    .prepare_captured_content_custody(first, holding)
    .captured_content_stage("first custody")
  original.persist(bytes).captured_content_stage("first persist")
  original.confirm(2).captured_content_stage("first confirm")
  assert_true(
    original.retry_cleanup().captured_content_stage("first I/O close"),
  )
  assert_true(original.matches_confirmed(first))
  assert_false(original.matches_confirmed(second))
  let next = store
    .prepare_captured_content_custody(second, holding)
    .captured_content_stage("second custody")
  next.persist(bytes).captured_content_stage("second materialization")
  assert_false(next.matches_confirmed(second))
  assert_false(next.matches_confirmed(first))
  assert_eq(next.generation, original.generation)
  assert_false(next.intent_owned)
  assert_false(next.reservation_attempted)
  next.confirm(3).captured_content_stage("second confirm")
  assert_true(next.matches_confirmed(second))
  assert_true(next.retry_cleanup().captured_content_stage("second I/O close"))
  let different = native_content_candidate(authority, b"differ")
  let mismatch = store
    .prepare_captured_content_custody(different, holding)
    .captured_content_stage("mismatched custody")
  assert_true(mismatch.persist(b"differ") is Err(RecoveryRequired))
  assert_false(mismatch.matches_confirmed(different))
  assert_true(
    mismatch.retry_cleanup().captured_content_stage("mismatched I/O close"),
  )
  let usage = store.capacity_usage().captured_content_stage("durable holding")
  assert_eq(usage.reserved_bytes, 6L)
  assert_eq(usage.reserved_objects, 1L)
  assert_true(original.matches_confirmed(first))
  assert_true(store.close().captured_content_stage("Store close"))
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "Native equal Content reuse preserves the original quota read failure" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = @sqlite.load_library(path).captured_content_stage("library")
  let (store, authority, _) = native_content_store_fixture(
    "captured-content-missing-quota", 6L, library,
  )
  let bytes = b"shared"
  let first = native_content_candidate(authority, bytes)
  let holding = native_payload_cid("captured-content-missing-quota-holding")
  let original = store
    .prepare_captured_content_custody(first, holding)
    .captured_content_stage("original custody")
  original.persist(bytes).captured_content_stage("original persist")
  original.confirm(2).captured_content_stage("original confirm")
  assert_true(original.retry_cleanup().captured_content_stage("original close"))
  // Only the fixture removes the quota record. The exact sealed record and
  // file remain, so reuse reaches the original quota read after the collision.
  let _ = store.database
    .release_capacity("publication_payload", original.key, 6L, 1L)
    .captured_content_stage("fixture removes quota")
  let second = native_content_candidate(authority, bytes)
  let next = store
    .prepare_captured_content_custody(second, holding)
    .captured_content_stage("second custody")
  assert_true(next.persist(bytes) is Err(Database(@sqlite.NotFound)))
  assert_false(next.intent_owned)
  assert_false(next.reservation_attempted)
  assert_false(next.matches_confirmed(second))
  assert_true(next.retry_cleanup().captured_content_stage("second close"))
  assert_true(original.matches_confirmed(first))
  assert_true(store.close().captured_content_stage("Store close"))
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "Native captured Content capacity refusal retires only its original pending attempt" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("Missing explicit Native Content SQLite library")
  }
  let library = @sqlite.load_library(path).captured_content_stage(
    "Content original library",
  )
  native_content_physical_case_2(library)
  // This stock Library cannot issue the selected-component cleanup ACK.
  // Store/Writer/Reader close assertions above cover their original owners.
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
fn native_content_physical_case_2(library : @sqlite.Library) -> Unit raise {
  let (store, authority, _) = native_content_store_fixture(
    "captured-content-capacity", 8L, library,
  )
  let bytes = b"123456789"
  let candidate = native_content_candidate(authority, bytes)
  let holding = native_payload_cid("captured-content-capacity-holding")
  let custody = store
    .prepare_captured_content_custody(candidate, holding)
    .captured_content_stage("Content stage 21")
  assert_true(custody.persist(bytes) is Err(Database(@sqlite.CapacityExceeded)))
  assert_true(store.close() is Err(CleanupPending))
  let other = store
    .prepare_captured_content_custody(candidate, holding)
    .captured_content_stage("Content stage 22")
  assert_true(other.persist(bytes) is Err(RecoveryRequired))
  assert_true(other.retry_cleanup().captured_content_stage("Content stage 23"))
  assert_true(store.close() is Err(CleanupPending))
  assert_true(
    custody.retry_cleanup().captured_content_stage("Content stage 24"),
  )
  assert_false(custody.matches_confirmed(candidate))
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 25").reserved_bytes,
    0L,
  )
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 26").reserved_objects,
    0L,
  )
  assert_true(store.close().captured_content_stage("Content stage 27"))
}

///|
test "Native captured Content failure before terminal commit cancels only its acquired sealed Writer" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("Missing explicit Native Content SQLite library")
  }
  let library = @sqlite.load_library(path).captured_content_stage(
    "Content original library",
  )
  native_content_physical_case_3(library)
  // This stock Library cannot issue the selected-component cleanup ACK.
  // Store/Writer/Reader close assertions above cover their original owners.
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
fn native_content_physical_case_3(library : @sqlite.Library) -> Unit raise {
  let (store, authority, _) = native_content_store_fixture(
    "captured-content-before-commit", 64L, library,
  )
  let bytes = b"notes"
  let candidate = native_content_candidate(authority, bytes)
  let custody = store
    .prepare_captured_content_custody(
      candidate,
      native_payload_cid("content-before-holding"),
    )
    .captured_content_stage("Content stage 30")
  store.allocation_failure.val = Some(step => {
    if step == "captured-content-terminal" {
      Some(StateCollision)
    } else {
      None
    }
  })
  assert_true(custody.persist(bytes) is Err(StateCollision))
  store.allocation_failure.val = None
  assert_true(
    store.root
    .inspect_generation(custody.name)
    .captured_content_stage("Content stage 31")
    is Some(_),
  )
  assert_false(custody.matches_confirmed(candidate))
  assert_true(
    custody.retry_cleanup().captured_content_stage("Content stage 32"),
  )
  assert_true(
    store.root
    .inspect_generation(custody.name)
    .captured_content_stage("Content stage 33")
    is None,
  )
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 34").reserved_bytes,
    0L,
  )
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 35").reserved_objects,
    0L,
  )
  assert_true(store.close().captured_content_stage("Content stage 36"))
}

///|
test "Native captured Content failed terminal return preserves the actual committed generation and quota" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("Missing explicit Native Content SQLite library")
  }
  let library = @sqlite.load_library(path).captured_content_stage(
    "Content original library",
  )
  native_content_physical_case_4(library)
  // This stock Library cannot issue the selected-component cleanup ACK.
  // Store/Writer/Reader close assertions above cover their original owners.
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
fn native_content_physical_case_4(library : @sqlite.Library) -> Unit raise {
  let (store, authority, _) = native_content_store_fixture(
    "captured-content-after-commit", 64L, library,
  )
  let bytes = b"notes"
  let candidate = native_content_candidate(authority, bytes)
  let custody = store
    .prepare_captured_content_custody(
      candidate,
      native_payload_cid("content-after-holding"),
    )
    .captured_content_stage("Content stage 39")
  store.allocation_failure.val = Some(step => {
    if step == "captured-content-terminal-return" {
      Some(StateCollision)
    } else {
      None
    }
  })
  assert_true(custody.persist(bytes) is Err(StateCollision))
  store.allocation_failure.val = None
  let generation = store.root
    .inspect_generation(custody.name)
    .captured_content_stage("Content stage 40")
  assert_true(generation is Some(_))
  assert_false(custody.matches_confirmed(candidate))
  assert_true(
    custody.retry_cleanup().captured_content_stage("Content stage 41"),
  )
  assert_eq(
    store.root
    .inspect_generation(custody.name)
    .captured_content_stage("Content stage 42"),
    generation,
  )
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 43").reserved_bytes,
    5L,
  )
  assert_eq(
    store.capacity_usage().captured_content_stage("Content stage 44").reserved_objects,
    1L,
  )
  // This confirms physical byte retention only. It never changes the original
  // failed outcome into success or supplies permission to restart that Source.
  assert_false(custody.matches_confirmed(candidate))
  assert_true(store.close().captured_content_stage("Content stage 45"))
}

///|
test "Native captured Content empty bytes retain one real object through Store recovery" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("Missing explicit Native Content SQLite library")
  }
  let library = @sqlite.load_library(path).captured_content_stage(
    "empty Content library",
  )
  let (store, authority, _) = native_content_store_fixture(
    "empty-content", 0L, library,
  )
  let original = native_content_candidate(authority, b"")
  let custody = store
    .prepare_captured_content_custody(
      original,
      native_payload_cid("empty-content-holding"),
    )
    .captured_content_stage("empty Content custody")
  custody.persist(b"").captured_content_stage("empty Content persist")
  custody.confirm(1).captured_content_stage("empty Content confirm")
  assert_true(custody.matches_confirmed(original))
  assert_true(
    custody
    .retry_cleanup()
    .captured_content_stage("empty Content I/O retirement"),
  )
  let recovery = store
    .recover()
    .captured_content_stage("empty Content Store recovery")
  assert_eq(recovery.retained, 1)
  assert_eq(recovery.reclaimed, 0)
  let usage = store
    .capacity_usage()
    .captured_content_stage("empty Content quota")
  assert_eq(usage.reserved_bytes, 0L)
  assert_eq(usage.reserved_objects, 1L)
  assert_true(store.close().captured_content_stage("empty Content Store close"))
  // This stock Library is not a selected-component cleanup ACK.
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "Native Content canonical record geometry preserves extreme originals and malformed refusal" {
  let holding = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  assert_eq(captured_content_record_bound("x", 65536), Some(207))
  assert_eq(captured_content_record_bound("x", 65536, retiring=true), Some(208))
  let bodies = [
    (
      "x", "[\"actql-native-captured-content-custody/0.1\",\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"x\",\"sealed\",\"18446744073709551615\",\"18446744073709551615\",\"9223372036854775807\"]",
    ),
    (
      "\u{0001}", "[\"actql-native-captured-content-custody/0.1\",\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"\\u0001\",\"sealed\",\"18446744073709551615\",\"18446744073709551615\",\"9223372036854775807\"]",
    ),
    (
      "😀", "[\"actql-native-captured-content-custody/0.1\",\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"😀\",\"sealed\",\"18446744073709551615\",\"18446744073709551615\",\"9223372036854775807\"]",
    ),
  ]
  for (wire, original) in bodies {
    let body = @utf8.encode(original)
    assert_true(
      body.length() <= captured_content_record_bound(wire, 65536).unwrap(),
    )
    let generation = captured_content_generation(body, holding, wire, 65536).unwrap()
    assert_eq(generation.device.to_string(), "18446744073709551615")
    assert_eq(generation.inode.to_string(), "18446744073709551615")
    assert_eq(generation.size, 9223372036854775807L)
    // This noncanonical body is below the geometry bound: the original
    // canonical equality guard, rather than just the preparse size, refuses.
    assert_true(
      captured_content_generation(
        @utf8.encode(" " + original),
        holding,
        wire,
        65536,
      )
      is Err(StateCollision),
    )
    // The raw readback remains within the old Store bound, but cannot be
    // the canonical original. It refuses before parser/index construction.
    assert_true(
      captured_content_generation(
        @utf8.encode(" ".repeat(512) + original),
        holding,
        wire,
        65536,
      )
      is Err(StateCollision),
    )
  }
}

///|
test "Native captured Content retained inventory keeps original records and actual Map backing after I/O" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = @sqlite.load_library(path).captured_content_stage(
    "retained library",
  )
  let (store, authority, _) = native_content_store_fixture(
    "retained-original",
    16L,
    library,
    diagnostic_ceiling=Some(128),
  )
  let bytes = b"original"
  let original = native_content_candidate(authority, bytes)
  let child = store
    .prepare_captured_content_custody(
      original,
      native_payload_cid("retained-original-holding"),
    )
    .captured_content_stage("retained child")
  assert_true(child.retained_inventory() is None)
  child.persist(bytes).captured_content_stage("retained persist")
  child.confirm(2).captured_content_stage("retained confirm")
  assert_true(child.retained_inventory() is None)
  assert_true(child.retry_cleanup().captured_content_stage("retained cleanup"))
  let inventory = child.retained_inventory().unwrap()
  // Original Map retains its actual allocated buckets even after entry removal.
  assert_eq(store.active_writers.length(), 0)
  assert_true(store.active_writers.capacity() > 0)
  assert_eq(
    inventory.reference_slots,
    19L + store.active_writers.capacity().to_int64(),
  )
  assert_eq(inventory.record_headers, 11L)
  assert_eq(inventory.scalar_words, 19L)
  assert_eq(
    inventory.owned_wire_bytes,
    child.intent.length().to_int64() + child.retired_record.length().to_int64(),
  )
  assert_eq(
    inventory.owned_utf16_units,
    child.key.length().to_int64() +
    child.staging.length().to_int64() +
    child.name.length().to_int64(),
  )
  assert_true(child.matches_confirmed(original))
  assert_true(store.close().captured_content_stage("retained Store close"))
  assert_true(child.retained_inventory() is None)
  assert_true(library.close_checked() is Err(@sqlite.Physical(_)))
}

///|
test "Native unpublished generated Content retires its exact sealed file and quota" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let library = @sqlite.load_library(path).captured_content_stage(
    "generated Content library",
  )
  let (store, authority, store_path) = native_content_store_fixture(
    "unpublished-generated-content",
    18L,
    library,
    diagnostic_ceiling=Some(512),
  )
  let limits : @admitted.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let (candidate, output) = native_generated_jsonl(authority, limits)
  let holding = native_payload_cid("unpublished-generated-content")
  let custody = store
    .prepare_generated_content_custody(candidate, holding)
    .unwrap()
  custody.persist_generated_output(output).unwrap()
  custody.confirm(4).unwrap()
  let generation = custody.generation.unwrap()
  assert_true(store.root.verify_generation(custody.name, generation))
  assert_true(custody.matches_generated_confirmed(candidate))
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 1L)
  assert_true(custody.abandon_unpublished_generated().unwrap())
  assert_true(custody.abandon_unpublished_generated().unwrap())
  assert_false(custody.matches_generated_confirmed(candidate))
  assert_true(store.root.inspect_generation(custody.name).unwrap() is None)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 0L)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
  let reopened = open_existing_store_with_custody(
    library,
    store_path,
    authority,
    18L,
    8L,
    65536L,
    diagnostic_ceiling=Some(512),
  ).captured_content_stage("reopen after retirement")
  assert_eq(reopened.capacity_usage().unwrap().reserved_objects, 0L)
  assert_true(reopened.close().unwrap())
}
