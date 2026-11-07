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
  let store = open_store(library, selected, authority, capacity, 8L, 65536L).captured_content_stage(
    "Content Store open",
  )
  (store, authority, selected)
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
