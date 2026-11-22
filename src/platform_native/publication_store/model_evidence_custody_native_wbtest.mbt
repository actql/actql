///|
fn native_model_evidence_test_outcome(
  category : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(
    "model_attempt_outcome",
    "{\"attempt_cid\":\"sha256:" +
    "c".repeat(64) +
    "\",\"category\":\"" +
    category +
    "\",\"failure\":null,\"slot_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"version\":\"actql-model-attempt-outcome/0.1\"}",
    16384,
    256,
    8,
  ).unwrap()
}

///|
test "Native Model Raw custody encrypts exact binary response and confirms the original cell" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture("model-raw-evidence", 65536L)
    is Some((store, authority, library, root)) else {
    abort(
      "Native Model Raw custody requires an isolated Store and crypto fixture",
    )
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  // Physical projection fixture only. In production the Store obtains all
  // five fields from a Common-bound descriptor, under that original authority.
  let cid = "sha256:" + "a".repeat(64)
  let holding = "sha256:" + "b".repeat(64)
  let descriptor = "{\"http_status\":429}"
  let content = "sha256:53d9a2dfbbf01d69b132e7d141e5c7b8cafaa464fc86eff90b1091b7a0439f7f"
  let bytes = b"\x00\xff\x80\xa0x\n"
  let selection = (cid, holding, descriptor, content, 6)
  let baseline = store.capacity_usage().unwrap().reserved_bytes
  assert_true(
    store.prepare_model_raw_payload_in_scope(
      selection, b"\x00\xff\x80\xa0x!", crypto, key,
    )
    is Err(DigestMismatch),
  )
  assert_true(
    store.prepare_model_raw_payload_in_scope(selection, b"", crypto, key)
    is Err(DigestMismatch),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, baseline)
  let custody = store
    .prepare_model_raw_payload_in_scope(selection, bytes, crypto, key)
    .unwrap()
  assert_true(custody.read() is Err(Database(@sqlite.NotFound)))
  custody.persist().unwrap()
  let (encrypted, retired) = custody.read().unwrap()
  assert_false(retired)
  let expected = b"{\"http_status\":429}\nAP+AoHgK"
  assert_true(encrypted.body != expected)
  assert_eq(
    crypto
    .open_private_evidence(key, "model_raw_response", cid, encrypted.body)
    .unwrap(),
    expected,
  )
  assert_true(
    crypto.open_private_evidence(
      key,
      "model_attempt_outcome",
      cid,
      encrypted.body,
    )
    is Err(CipherRejected),
  )
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    baseline + custody.reservation_bytes,
  )
  assert_true(store.close().unwrap())
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let original = reopened
    .prepare_model_raw_payload_in_scope(selection, bytes, crypto, key)
    .unwrap()
  original.persist().unwrap()
  let (confirmed, retired) = original.read().unwrap()
  assert_false(retired)
  assert_eq(confirmed.body, encrypted.body)
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_bytes,
    baseline + custody.reservation_bytes,
  )
  assert_true(reopened.close().unwrap())
}

///|
// Actual SQLite/filesystem/AEAD Store, with authored evidence and Scope DATA.
// This does not claim original Model invocation, Journal settlement or ACK.
test "Native Model evidence preserves ciphertext and quota across reopen and failed retirement" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture("model-evidence", 65536L)
    is Some((store, authority, library, root)) else {
    abort(
      "Native Model evidence requires its original isolated Store and crypto fixture",
    )
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let definition = native_commit_fixture(store, authority, "model-evidence").run_definition
  let scope = "sha256:" + "a".repeat(64)
  let slot = "sha256:" + "b".repeat(64)
  let attempt = "sha256:" + "c".repeat(64)
  let original = native_model_evidence_test_outcome("ok")
  let baseline = store.capacity_usage().unwrap().reserved_bytes
  let custody = store
    .prepare_model_evidence_custody(
      definition, scope, slot, attempt, original, crypto, key,
    )
    .unwrap()
  assert_true(custody.confirm() is Err(Database(@sqlite.NotFound)))
  custody.persist().unwrap()
  let reserved = custody.reserved_bytes()
  assert_true(reserved > 0L)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, baseline + reserved)
  let holding = custody.private_custody.holding
  let encrypted = store.database
    .read("model_evidence_custody", holding)
    .unwrap()
  assert_true(
    encrypted.body !=
    @utf8.encode(@publication.run_evidence_value_json(original)),
  )
  assert_eq(
    @publication.run_evidence_value_identity(custody.confirm().unwrap()),
    @publication.run_evidence_value_identity(original),
  )
  // Same immutable cell: a fresh constructor/nonce cannot overwrite its bytes.
  let same = store
    .prepare_model_evidence_custody(
      definition, scope, slot, attempt, original, crypto, key,
    )
    .unwrap()
  same.persist().unwrap()
  assert_eq(
    store.database.read("model_evidence_custody", holding).unwrap().body,
    encrypted.body,
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, baseline + reserved)
  store.close().unwrap() |> ignore
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let restored = reopened
    .restore_model_evidence_custody(
      definition, scope, slot, attempt, original, crypto, key,
    )
    .unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(restored.confirm().unwrap()),
    @publication.run_evidence_value_identity(original),
  )
  assert_true(
    reopened.restore_model_evidence_custody(
      definition,
      "sha256:" + "d".repeat(64),
      slot,
      attempt,
      original,
      crypto,
      key,
    )
    is Err(Database(@sqlite.NotFound)),
  )
  assert_true(
    reopened.restore_model_evidence_custody(
      definition,
      scope,
      slot,
      attempt,
      original,
      crypto,
      Bytes::make(32, 0),
    )
    is Err(PrivateEvidence(@signature.CipherRejected)),
  )
  // A conflicting admitted outcome cannot replace or retire the old one.
  let conflicting = reopened
    .prepare_model_evidence_custody(
      definition,
      scope,
      slot,
      attempt,
      native_model_evidence_test_outcome("result_unknown"),
      crypto,
      key,
    )
    .unwrap()
  assert_true(conflicting.persist() is Err(_))
  assert_true(conflicting.retry_cleanup() is Err(_))
  assert_eq(
    reopened.database.read("model_evidence_custody", holding).unwrap().body,
    encrypted.body,
  )
  reopened.allocation_failure.val = Some(step => {
    if step == "model-evidence-before-capacity-release" {
      Some(StateCollision)
    } else {
      None
    }
  })
  assert_true(restored.retry_cleanup() is Err(StateCollision))
  assert_true(restored.confirm() is Err(RecoveryRequired))
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_bytes,
    baseline + reserved,
  )
  reopened.close().unwrap() |> ignore
  let final_store = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let pending = final_store
    .restore_model_evidence_custody(
      definition, scope, slot, attempt, original, crypto, key,
    )
    .unwrap()
  assert_true(pending.persist() is Err(RecoveryRequired))
  assert_true(pending.retry_cleanup().unwrap())
  assert_false(pending.retry_cleanup().unwrap())
  assert_eq(final_store.capacity_usage().unwrap().reserved_bytes, baseline)
  assert_true(final_store.close().unwrap())
}
