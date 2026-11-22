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
    is InitialStorageClaim(original, signing_use) else {
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
  (key, original, signing_use, physical, standard)
}

///|
test "initial original signature and exact terminal outcome share one confirmed Host transaction" {
  let (key, original, signing_use, physical, signature) = initial_resolution_physical_fixture(
    "initial-signature-confirmed",
  )
  let host = key.original.host
  host.journal
  .transaction(() => {
    store_local_initial_resolution_signature_locked(
      host, original, signing_use, signature,
    )
  })
  .unwrap()
  let restored = host.journal
    .transaction(() => {
      local_initial_resolution_signature_locked(host, original, signing_use)
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
    @credential.local_signing_credential_use_cid(signing_use),
  )
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  physical.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "initial signature storage rolls back a foreign use and rejects a changed authenticated packet" {
  let (key, original, signing_use, physical, signature) = initial_resolution_physical_fixture(
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
      host, original, signing_use, signature,
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
      local_initial_resolution_signature_locked(host, original, signing_use)
    })
    is Err(CustodyLost),
  )
  physical.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "lost signature commit return retains original signature and outcome on same-process Host reopen" {
  let name = "initial-signature-commit-return"
  let (key, original, signing_use, physical, signature) = initial_resolution_physical_fixture(
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
        host, original, signing_use, signature,
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
      local_initial_resolution_signature_locked(reopened, original, signing_use)
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

///|
// Real SQLite/signature ports. The same operation bundle below is explicit
// diagnostic input, not a captured Account or public approval qualification.
test "Initial signature storage and original read retain the same routed Run decoder and writes" {
  let (key, original, signing_use, physical, signature) = initial_resolution_physical_fixture(
    "initial-signature-routed",
  )
  let host = key.original.host
  let calls : Array[String] = []
  let decoded = Ref(0)
  let access = journal_test_operation_access(host.database, calls)
  let access = {
    ..access,
    reads: {
      ..access.reads,
      before_run_decode: Some(_ => {
        decoded.val += 1
        Ok(())
      }),
    },
  }
  host.journal
  .transaction_with_reads(
    () => {
      store_local_initial_resolution_signature_locked(
        host,
        original,
        signing_use,
        signature,
        operations=Some(access),
      )
    },
    reads=Some(access.reads),
  )
  .unwrap()
  assert_true(decoded.val > 0)
  assert_true(
    calls.contains(
      "insert:client_local_signing_result_originals:" + original.operation_cid,
    ),
  )
  assert_true(
    calls.contains(
      "read:client_local_signing_result_originals:" + original.operation_cid,
    ),
  )
  assert_true(calls.contains("capacity:client_local_grant_originals"))
  assert_eq(
    host.journal
    .transaction_with_reads(
      () => {
        local_initial_resolution_signature_locked(
          host,
          original,
          signing_use,
          reads=Some(access.reads),
        )
      },
      reads=Some(access.reads),
    )
    .unwrap(),
    signature,
  )
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  let crypto = host.epoch.crypto
  physical.close_checked().unwrap()
  host.close().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "Initial routed signature lost commit retains Unknown and cannot enter another signer" {
  let (key, original, signing_use, physical, signature) = initial_resolution_physical_fixture(
    "initial-signature-routed-unknown",
  )
  let host = key.original.host
  let calls : Array[String] = []
  let access = journal_test_operation_access(host.database, calls)
  client_test_fail_commit_reply(host.database, 1)
  let result = host.journal.transaction_with_reads(
    () => {
      store_local_initial_resolution_signature_locked(
        host,
        original,
        signing_use,
        signature,
        operations=Some(access),
      )
    },
    reads=Some(access.reads),
  )
  assert_true(result is Err(TransactionUnknown))
  assert_true(host.journal.fenced)
  assert_true(
    calls.contains(
      "insert:client_local_signing_result_originals:" + original.operation_cid,
    ),
  )
  assert_true(
    host.journal.transaction_with_reads(
      () => {
        local_initial_resolution_signature_locked(
          host,
          original,
          signing_use,
          reads=Some(access.reads),
        )
      },
      reads=Some(access.reads),
    )
    is Err(Fenced),
  )
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  let crypto = host.epoch.crypto
  physical.close_checked().unwrap()
  host.close().unwrap()
  crypto.close_checked().unwrap()
}

///|
// Closed DATA at the actual return helpers, not a fabricated Host/capture.
test "Initial signing routed return preserves original primary and refuses a failed Read after inner success" {
  assert_true(
    finish_initial_resolution_signing_read(
      Some(Err(OriginalSigningJournal(ChangedIntent))),
      Err(CustodyLost),
    )
    is Err(OriginalSigningJournal(ChangedIntent)),
  )
  assert_true(
    finish_initial_resolution_signing_read(
      Some(Ok("original wire")),
      Err(OriginalResourceScopePending),
    )
    is Err(OriginalSigningOriginal(OriginalResourceScopePending)),
  )
  assert_eq(
    finish_initial_resolution_signing_read(Some(Ok("original wire")), Ok(())).unwrap(),
    "original wire",
  )
  let host_primary : Result[String, NativeLocalInitialHostAttestationIssue]? = Some(
    Err(HostAttestationJournal(ChangedIntent)),
  )
  assert_true(
    finish_initial_host_signing_read(host_primary, Err(CustodyLost))
    is Err(HostAttestationJournal(ChangedIntent)),
  )
  assert_true(
    finish_initial_host_signing_read(
      Some(Ok("original wire")),
      Err(OriginalResourceScopePending),
    )
    is Err(HostAttestationOriginal(OriginalResourceScopePending)),
  )
}

///|
test "Initial signing routed return retains combined Read failure and original commit Unknown" {
  let combined : NativeLocalAdoptionIssue = InstallationReadTransactionFailure(
    OriginalResourceScopePending,
    TransactionUnknown,
  )
  assert_true(
    finish_initial_resolution_signing_read(
      Some(Err(OriginalSigningJournal(TransactionUnknown))),
      Err(combined),
    )
    is Err(
      OriginalSigningOriginal(
        InstallationReadTransactionFailure(
          OriginalResourceScopePending,
          TransactionUnknown
        )
      )
    ),
  )
  let host_unknown : Result[String, NativeLocalInitialHostAttestationIssue]? = Some(
    Err(HostAttestationJournal(TransactionUnknown)),
  )
  assert_true(
    finish_initial_host_signing_read(host_unknown, Err(combined))
    is Err(
      HostAttestationOriginal(
        InstallationReadTransactionFailure(
          OriginalResourceScopePending,
          TransactionUnknown
        )
      )
    ),
  )
}
