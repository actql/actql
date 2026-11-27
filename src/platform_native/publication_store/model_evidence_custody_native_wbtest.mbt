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
test "Native dependent Model reobserves only the original entered Raw payload" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture("model-entered-proof", 65536L)
    is Some((store, authority, library, root)) else {
    abort("Native entered Model Raw requires its isolated Store and Crypto")
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let cid = "sha256:" + "a".repeat(64)
  let holding = "sha256:" + "b".repeat(64)
  let descriptor = "{\"http_status\":200}"
  let bytes = b"\x00\xff\x80\xa0x\n"
  let selected = (
    cid,
    holding,
    descriptor,
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
  )
  let table = "model_evidence_custody"
  assert_true(
    store.observe_entered_model_raw_extent(selected)
    is Err(Database(@sqlite.NotFound)),
  )
  let original = store
    .prepare_model_raw_payload_in_scope(selected, bytes, crypto, key)
    .unwrap()
  original.persist().unwrap()
  let committed = store.database.read(table, holding).unwrap()
  assert_eq(committed.revision, 0L)
  let usage = store.capacity_usage().unwrap()
  assert_true(store.close().unwrap())
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let (extent, quote) = reopened
    .observe_entered_model_raw_extent(selected)
    .unwrap()
  assert_eq(quote.envelope_bytes, committed.body.length())
  assert_true(
    quote.workspace.owned_wire_bytes > committed.body.length().to_int64(),
  )
  extent.verify_original(crypto, key).unwrap()
  assert_true(
    extent.verify_original(crypto, Bytes::make(32, 0))
    is Err(PrivateEvidence(_)),
  )
  // Model a same-generation replacement in the exact physical cell. This
  // ciphertext has the right length and authenticates under the same AAD;
  // its different body still fails the committed descriptor's content CID.
  let other = crypto
    .seal_private_evidence(
      key,
      "model_raw_response",
      cid,
      @utf8.encode(descriptor + "\n" + @base64.encode(b"\x00\xff\x80\xa0x!")),
    )
    .unwrap()
  assert_eq(other.length(), committed.body.length())
  reopened.database.begin_immediate().unwrap()
  reopened.database.remove_exact(table, holding, 0L, committed.body).unwrap()
  assert_eq(reopened.database.insert(table, holding, other).unwrap(), 0L)
  reopened.database.commit().unwrap()
  assert_true(extent.verify_original(crypto, key) is Err(DigestMismatch))
  reopened.database.begin_immediate().unwrap()
  reopened.database.remove_exact(table, holding, 0L, other).unwrap()
  assert_eq(
    reopened.database.insert(table, holding, committed.body).unwrap(),
    0L,
  )
  assert_eq(
    reopened.database
    .compare_exchange(table, holding, 0L, committed.body)
    .unwrap(),
    1L,
  )
  reopened.database.commit().unwrap()
  assert_true(extent.verify_original(crypto, key) is Err(Database(_)))
  assert_true(
    reopened.observe_entered_model_raw_extent(selected) is Err(RecoveryRequired),
  )
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_bytes,
    usage.reserved_bytes,
  )
  assert_true(reopened.close().unwrap())
}

///|
test "Native settled Model Raw descriptor reopens the exact bounded cell" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture("model-raw-descriptor", 65536L)
    is Some((store, authority, library, root)) else {
    abort("Native Raw descriptor requires its isolated Store and Crypto")
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let definition = native_commit_fixture(
      store, authority, "model-raw-descriptor",
    ).run_definition
  let definition_cid = @publication.publication_contract_identity(definition)
  let scope = "sha256:" + "a".repeat(64)
  let slot = "sha256:" + "b".repeat(64)
  let attempt = "sha256:" + "c".repeat(64)
  let policy = "sha256:" + "d".repeat(64)
  let profile = "sha256:" + "e".repeat(64)
  let bytes = Bytes::make(4096, b'R')
  let content = "sha256:" + @sha.hex(bytes)
  let body =
    $|{"attempt":1,"attempt_cid":"\{attempt}","byte_count":4096,"content_cid":"\{content}","effective_data_policy_cid":"\{policy}","http_status":429,"observed_at":"2026-10-12T00:00:01.000Z","phase":"entered","raw_capture_policy_cid":"\{policy}","response_profile_cid":"\{profile}","run_definition_cid":"\{definition_cid}","scope_cid":"\{scope}","slot_cid":"\{slot}","store_authority_cid":"\{authority}","transport_eof":true,"version":"actql-model-raw-response/0.1"}
  let original = @publication.seal_run_evidence_value(
    "model_raw_response", body, 8192, 128, 8,
  ).unwrap()
  let cid = @publication.run_evidence_value_identity(original)
  let wire = @publication.run_evidence_value_json(original)
  let entered = @publication.model_scoped_private_holding_cid(
    definition, authority, scope, slot, attempt, 1, "entered", "model_raw_response",
  ).unwrap()
  let settled = @publication.model_scoped_private_holding_cid(
    definition, authority, scope, slot, attempt, 1, "settled", "model_raw_response",
  ).unwrap()
  // An authored canonical descriptor alone cannot enter the warm writer.
  assert_true(
    store.prepare_model_evidence_custody(
      definition, scope, slot, attempt, original, crypto, key,
    )
    is Err(StateCollision),
  )
  let raw = store
    .prepare_model_raw_payload_in_scope(
      (cid, entered, wire, content, bytes.length()),
      bytes,
      crypto,
      key,
    )
    .unwrap()
  raw.persist().unwrap()
  assert_true(
    store.model_settlement_restore_construction(
      definition,
      scope,
      slot,
      attempt,
      RawDescriptor,
      cid,
    )
    is Err(Database(@sqlite.NotFound)),
  )
  // Install the independent evidence fixture under the same private commit
  // owner that production calls after accepting the original Raw receipt.
  let descriptor = prepare_private_effect_custody(
    store, settled, model_raw_descriptor_aad_role, cid, wire, "model_evidence_custody",
    "model-evidence", "{\"cleanup_complete\":true}", crypto, key,
  ).unwrap()
  descriptor.persist().unwrap()
  let full_size = raw.reservation_bytes
  let usage = store.capacity_usage().unwrap()
  assert_true(store.close().unwrap())
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let (extent, quote) = reopened
    .model_settlement_restore_construction(
      definition,
      scope,
      slot,
      attempt,
      RawDescriptor,
      cid,
    )
    .unwrap()
  assert_true(extent.header.body_bytes < full_size)
  assert_true(quote.retained.owned_utf16_units >= wire.length().to_int64())
  assert_eq(extent.read_original_wire(crypto, key).unwrap(), wire)
  assert_true(
    extent.read_original_wire(crypto, Bytes::make(32, 0))
    is Err(PrivateEvidence(_)),
  )
  assert_true(
    reopened.model_settlement_restore_construction(
      definition,
      scope,
      slot,
      "sha256:" + "f".repeat(64),
      RawDescriptor,
      cid,
    )
    is Err(Database(@sqlite.NotFound)),
  )
  let (wrong_cid, _) = reopened
    .model_settlement_restore_construction(
      definition,
      scope,
      slot,
      attempt,
      RawDescriptor,
      "sha256:" + "f".repeat(64),
    )
    .unwrap()
  assert_true(
    wrong_cid.read_original_wire(crypto, key) is Err(PrivateEvidence(_)),
  )
  let wrong_role = {
    ..extent,
    holding: entered,
    header: reopened.database
    .observe_body_extent("model_evidence_custody", entered)
    .unwrap(),
  }
  assert_true(
    wrong_role.read_original_wire(crypto, key) is Err(PrivateEvidence(_)),
  )
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_bytes,
    usage.reserved_bytes,
  )
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_objects,
    usage.reserved_objects,
  )
  let retired = { ..descriptor, store: reopened, }
  assert_true(retired.retry_cleanup().unwrap())
  assert_true(extent.read_original_wire(crypto, key) is Err(Database(_)))
  assert_true(reopened.close().unwrap())
  crypto.close_checked().unwrap()
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
  assert_false(custody.reconcile_original_store_return().unwrap())
  assert_true(store.close().unwrap())
  assert_true(custody.reconcile_original_store_return().unwrap())
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let semantic_cid = @publication.run_evidence_value_identity(original)
  let (extent, quote) = reopened
    .model_settlement_restore_construction(
      definition,
      scope,
      slot,
      attempt,
      Outcome,
      semantic_cid,
    )
    .unwrap()
  let original_wire = @publication.run_evidence_value_json(original)
  assert_eq(extent.read_original_wire(crypto, key).unwrap(), original_wire)
  assert_true(
    quote.retained.owned_utf16_units >= original_wire.length().to_int64(),
  )
  assert_true(
    reopened.model_settlement_restore_construction(
      definition,
      scope,
      slot,
      attempt,
      Capture,
      semantic_cid,
    )
    is Err(Database(@sqlite.NotFound)),
  )
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
  assert_true(extent.read_original_wire(crypto, key) is Err(Database(_)))
  assert_true(
    reopened.model_settlement_restore_construction(
      definition,
      scope,
      slot,
      attempt,
      Outcome,
      semantic_cid,
    )
    is Err(RecoveryRequired),
  )
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
