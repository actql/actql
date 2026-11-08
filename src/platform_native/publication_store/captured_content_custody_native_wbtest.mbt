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
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    fail("Missing explicit Native Content Store fixture")
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
fn native_content_candidate(
  authority : String,
  bytes : Bytes,
) -> @publication.CapturedContentReference raise {
  let binding : @publication.GeneratedContentBinding = {
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
  @publication.prepare_captured_content_reference(
    binding,
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
    18L + store.active_writers.capacity().to_int64(),
  )
  assert_eq(inventory.record_headers, 10L)
  assert_eq(inventory.scalar_words, 18L)
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
