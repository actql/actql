///|
// Private physical/storage connection only. The original Subject metadata is
// the existing explicit storage fixture, not a paired approval scope or proof
// of public current authorization. The public Materials factory remains opaque.
fn initial_resolution_physical_fixture(
  name : String,
) -> (
  NativeLocalInitialReviewerSigningKey,
  NativeLocalGrantOriginal,
  @credential.LocalSigningCredentialUse,
  @crypto.OriginalKeySigningAttempt,
  String,
) raise {
  let (key, request, scope) = initial_issue_storage_fixture(name)
  let physical = prepare_local_initial_resolution_physical(key, scope).unwrap()
  guard initial_issue_storage_transaction(key, request, scope, () => 10000L).unwrap()
    is InitialStorageClaim(original, use) else {
    fail("fresh original signing claim required")
  }
  let transport = physical.sign_once().unwrap()
  assert_true(
    key.original.host.epoch.crypto
    .verify_ed25519(
      key.original.public_key_pem,
      @utf8.encode(scope.preimage),
      transport,
    )
    .unwrap(),
  )
  let standard = local_initial_resolution_signature_standard(transport).unwrap()
  (key, original, use, physical, standard)
}

///|
test "initial original signature and exact terminal outcome share one confirmed Host transaction" {
  let (key, original, use, physical, signature) = initial_resolution_physical_fixture(
    "initial-signature-confirmed",
  )
  let host = key.original.host
  host.journal
  .transaction(() => {
    store_local_initial_resolution_signature_locked(
      host, original, use, signature,
    )
  })
  .unwrap()
  let restored = host.journal
    .transaction(() => {
      local_initial_resolution_signature_locked(host, original, use)
    })
    .unwrap()
  assert_eq(restored, signature)
  guard original.grant is SigningGrant(grant) else {
    fail("expected original grant")
  }
  let history = @credential_resource.prepare_native_local_original_signing_history_candidate(
    host.database,
    grant,
  ).unwrap()
  assert_true(history.observed_outcome() is @credential_resource.Succeeded)
  assert_eq(
    @credential.local_signing_credential_use_cid(history.original_use()),
    @credential.local_signing_credential_use_cid(use),
  )
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  physical.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "initial signature storage rolls back a foreign use and rejects a changed authenticated packet" {
  let (key, original, use, physical, signature) = initial_resolution_physical_fixture(
    "initial-signature-foreign",
  )
  let host = key.original.host
  guard original.grant is SigningGrant(grant) else {
    fail("expected original grant")
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  // The default grant allows one use: a different canonical use ID is enough
  // to distinguish copied metadata from this exact already-claimed original.
  let foreign = @credential.prepare_local_signing_credential_use(
    grant, "foreign-use", 10000L, 0, false, scope,
  ).unwrap()
  assert_true(
    host.journal.transaction(() => {
      store_local_initial_resolution_signature_locked(
        host, original, foreign, signature,
      )
    })
    is Err(CustodyLost),
  )
  assert_true(
    host.database.read(
      "client_local_signing_result_originals",
      original.operation_cid,
    )
    is Err(@sqlite.NotFound),
  )
  let claimed = @credential_resource.prepare_native_local_original_signing_history_candidate(
    host.database,
    grant,
  ).unwrap()
  assert_true(claimed.observed_outcome() is @credential_resource.Claimed)
  host.journal
  .transaction(() => {
    store_local_initial_resolution_signature_locked(
      host, original, use, signature,
    )
  })
  .unwrap()
  let row = host.database
    .read("client_local_signing_result_originals", original.operation_cid)
    .unwrap()
  let envelope = local_adoption_fields(row.body, ["payload", "tag"]).unwrap()
  let bad_tag = if envelope[1].has_prefix("0") {
    "1" + envelope[1][1:].to_owned()
  } else {
    "0" + envelope[1][1:].to_owned()
  }
  let changed = local_adoption_record([
    ("payload", envelope[0]),
    ("tag", bad_tag),
  ]).unwrap()
  host.journal
  .transaction(() => {
    host.database
    .remove_exact(
      "client_local_signing_result_originals",
      original.operation_cid,
      row.revision,
      row.body,
    )
    .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
    .bind(_ => {
      host.database
      .insert(
        "client_local_signing_result_originals",
        original.operation_cid,
        changed,
      )
      .map(_ => ())
      .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
    })
  })
  .unwrap()
  assert_true(
    host.journal.transaction(() => {
      local_initial_resolution_signature_locked(host, original, use)
    })
    is Err(CustodyLost),
  )
  physical.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "lost signature commit return retains original signature and outcome on same-process Host reopen" {
  let name = "initial-signature-commit-return"
  let (key, original, use, physical, signature) = initial_resolution_physical_fixture(
    name,
  )
  let host = key.original.host
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    name
  let crypto = host.epoch.crypto
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    host.journal.transaction(() => {
      store_local_initial_resolution_signature_locked(
        host, original, use, signature,
      )
    })
    is Err(TransactionUnknown),
  )
  physical.close_checked().unwrap()
  host.close().unwrap()
  let session = begin_native_local_host_adoption(
    path,
    "store",
    path,
    "account.json",
    "operator",
    crypto,
    configuration_files=["host.json"],
    existing_only=true,
  ).unwrap()
  let reopened = session
    .open_journal(local_journal_test_library(), crypto, 10001.0, 8, 8388608L)
    .unwrap()
  let restored = reopened.journal
    .transaction(() => {
      local_initial_resolution_signature_locked(reopened, original, use)
    })
    .unwrap()
  assert_eq(restored, signature)
  guard original.grant is SigningGrant(grant) else {
    fail("expected original grant")
  }
  let history = @credential_resource.prepare_native_local_original_signing_history_candidate(
    reopened.database,
    grant,
  ).unwrap()
  assert_true(history.observed_outcome() is @credential_resource.Succeeded)
  assert_eq(
    @credential.local_signing_credential_use_projection(history.original_use()).2,
    1,
  )
  // Data readback after a lost return never calls the spent physical signer.
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  reopened.close().unwrap()
}
