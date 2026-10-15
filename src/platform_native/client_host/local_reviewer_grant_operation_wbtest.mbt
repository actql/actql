///|
// Real Host/SQLite/issuer Account and original public-key metadata. The
// synthetic descriptor and subject fields below exercise ONLY the shared
// append transaction. They cannot construct paired Reviewer materials, use
// the public adopt endpoint, sign or establish HostAttestation authority.
fn signing_append_fixture(
  name : String,
) -> (
  NativeLocalHostConnection,
  NativeLocalCredentialIssuerBinding,
  NativeLocalGrantOriginal,
) raise {
  let (host, key, original) = signing_grant_original_fixture(name)
  let issuer_file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  let issuer = signing_grant_fixture_require(
    host.acquire_credential_issuer(
      key.account.crypto,
      issuer_file.name,
      "operator",
      "cli",
      original.operation_cid,
    ),
    "independent_original_issuer",
  )
  (host, issuer, original)
}

///|
fn signing_append_storage_only(
  issuer : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
) -> Result[Unit, NativeClientRunJournalIssue] {
  issuer.host.journal.transaction(() => {
    issuer.append_owned_grant_original_locked(original, () => {
      issuer
      .require_current(issuer.host, issuer.operation_cid)
      .map_err(_ => AuthorizationDenied)
    })
  })
}

///|
test "Signing append shares the original logical reservation and exact immutable operation" {
  let (host, issuer, original) = signing_append_fixture("sign-append-original")
  let request_scope = @host.client_request_scope_cid(original.request)
  assert_false(
    local_original_grant_facts(original.grant).submission_scope_cid ==
    request_scope,
  )
  let before = run_record_body(
    host.journal.retained(original.request).unwrap().unwrap(),
  ).unwrap()
  signing_grant_fixture_require(
    signing_append_storage_only(issuer, original),
    "first_append",
  )
  let row_key = local_grant_original_key(
    issuer.crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  let row = host.database.read("client_local_grant_originals", row_key).unwrap()
  assert_eq(row.revision, 0L)
  assert_eq(row.body, local_grant_original_packet(original).unwrap())
  for _ in 0..<2 {
    signing_grant_fixture_require(
      signing_append_storage_only(issuer, original),
      "same_original_append",
    )
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  host.journal
  .transaction(() => {
    let (count, _, runs) = match host.local_grant_custody(issuer.crypto) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if count != 1 || runs.get(request_scope) is None {
      return Err(CustodyLost)
    }
    Ok(())
  })
  .unwrap()
  assert_eq(
    run_record_body(host.journal.retained(original.request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
}

///|
test "Signing append remains rejected by the unchanged HTTP operational entrypoint" {
  let (host, issuer, original) = signing_append_fixture("sign-append-not-http")
  let called = Ref(0)
  assert_true(
    host.journal.transaction(() => {
      issuer.append_grant_original_locked(original, () => {
        called.val += 1
        Ok(())
      })
    })
    is Err(AuthorizationDenied),
  )
  assert_eq(called.val, 0)
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  host.close().unwrap()
}

///|
test "Signing append refuses another operation for the same subject without replacing Unknown responsibility" {
  let (host, issuer, original) = signing_append_fixture("sign-append-second-op")
  signing_append_storage_only(issuer, original).unwrap()
  guard original.grant is SigningGrant(grant) else { fail("expected Signing") }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let second_grant = @credential.prepare_local_signing_credential_grant(
    issuer.selection.issuer_authority,
    { ..scope, attempt_id: "another-explicit-attempt", },
    @values.timestamp_epoch_milliseconds(issuer.selection.expires_at).unwrap(),
    issuer.selection.max_uses,
  ).unwrap()
  let second = local_owned_grant_original(
    issuer.crypto,
    "another-operation",
    original.request,
    original.issuer_selection_cid,
    SigningGrant(second_grant),
  ).unwrap()
  assert_true(
    signing_append_storage_only(issuer, second)
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  let cid = local_original_grant_cid(original.grant)
  // An unresolved original outcome is fixture evidence, not a signing action.
  host.database
  .insert("native-credential-outcome:" + cid, "unknown-original", b"unknown\n")
  .unwrap()
  |> ignore
  assert_true(
    signing_append_storage_only(issuer, second)
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  assert_eq(
    host.database
    .read("native-credential-outcome:" + cid, "unknown-original")
    .unwrap().body,
    b"unknown\n",
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  host.close().unwrap()
}

///|
test "Signing append changed intent under the same operation does not create another original" {
  let (host, issuer, original) = signing_append_fixture("sign-append-changed")
  signing_append_storage_only(issuer, original).unwrap()
  guard original.grant is SigningGrant(grant) else { fail("expected Signing") }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let changed_grant = @credential.prepare_local_signing_credential_grant(
    issuer.selection.issuer_authority,
    { ..scope, attempt_id: "changed-attempt", },
    @values.timestamp_epoch_milliseconds(issuer.selection.expires_at).unwrap(),
    issuer.selection.max_uses,
  ).unwrap()
  let changed = local_owned_grant_original(
    issuer.crypto,
    original.operation_id,
    original.request,
    original.issuer_selection_cid,
    SigningGrant(changed_grant),
  ).unwrap()
  assert_true(
    signing_append_storage_only(issuer, changed) is Err(ChangedIntent),
  )
  let key = local_grant_original_key(
    issuer.crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  assert_eq(
    host.database.read("client_local_grant_originals", key).unwrap().body,
    local_grant_original_packet(original).unwrap(),
  )
  host.close().unwrap()
}

///|
test "Signing append refusal rolls back its original capacity reservation" {
  let (host, issuer, original) = signing_append_fixture("sign-append-denied")
  assert_true(
    host.journal.transaction(() => {
      issuer.append_owned_grant_original_locked(original, () => {
        Err(AuthorizationDenied)
      })
    })
    is Err(AuthorizationDenied),
  )
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    0L,
  )
  host.close().unwrap()
}

///|
test "Signing append missing old reservation stays custody loss without repair" {
  let (host, issuer, original) = signing_append_fixture(
    "sign-append-lost-reservation",
  )
  signing_append_storage_only(issuer, original).unwrap()
  host.database
  .release_capacity(
    "client_local_grant_originals",
    @host.client_request_scope_cid(original.request),
    65536L,
    1L,
  )
  .unwrap()
  |> ignore
  assert_true(signing_append_storage_only(issuer, original) is Err(CustodyLost))
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  host.close().unwrap()
}

///|
test "Signing append lost commit ACK retains Unknown and never reissues" {
  let (host, issuer, original) = signing_append_fixture(
    "sign-append-unknown-ack",
  )
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    signing_append_storage_only(issuer, original) is Err(TransactionUnknown),
  )
  assert_true(host.journal.fenced)
  // No follow-up original lookup or another append in this fenced instance.
  // Closing owns cleanup; a future history reader must reconcile the original.
  host.close().unwrap()
}
