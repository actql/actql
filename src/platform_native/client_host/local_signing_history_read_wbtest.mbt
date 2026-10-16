///|
// Real original Host/Account/Root/SQLite and public PEM custody. The descriptor
// is synthetic, and Checkpoint/invocation fields below are metadata fixtures.
// This is history authorization, not an operational grant/signature/Approval.
fn signing_history_host_fixture(
  name : String,
  client_read? : Bool = true,
  retain_use? : Bool = true,
  retained_use_id? : String = "history-use",
  expires_at? : String = "2099-01-01T00:00:00.000Z",
) -> (
  NativeLocalHostConnection,
  NativeLocalSigningKeyOriginal,
  NativeLocalGrantOriginal,
) raise {
  let key_file = name + ".key.json"
  let descriptor = name + ".descriptor"
  let issuer_file = name + ".issuer.json"
  let reviewer_file = name + ".reviewer.json"
  let account_file = name + ".account.json"
  signing_original_write(
    key_file,
    @utf8.encode(
      signing_original_configuration(
        descriptor,
        signing_original_public_a,
        reviewer=true,
      ),
    ),
  )
  signing_original_write(descriptor, b"synthetic-file-projection-only")
  signing_original_write(
    issuer_file,
    @utf8.encode(
      local_issuer_fixture_wire.replace_all(
        old="2099-01-01T00:00:00.000Z",
        new=expires_at,
      ),
    ),
  )
  signing_original_write(
    reviewer_file,
    @utf8.encode(
      local_reviewer_selection_wire
      .replace_all(old="\"operator\"", new="\"reviewer\"")
      .replace_all(old="\"cli\"", new="\"review-cli\""),
    ),
  )
  let account = if client_read {
    reviewer_signing_scope_account
  } else {
    reviewer_signing_scope_account.replace_all(
      old="\"entry_id\":\"original-client-read\",\"outcome\":\"allow\"",
      new="\"entry_id\":\"original-client-read\",\"outcome\":\"deny\"",
    )
  }
  signing_original_write(account_file, @utf8.encode(account))
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  signing_grant_fixture_require(
    parent.create_directory(name + ".parent"),
    "parent_child",
  )
  |> ignore
  // The raw32 public projection requires this existing bounded diagnostic
  // selection, exactly as the original key-custody fixture. No secret is read.
  let crypto = signing_grant_fixture_require(
    @crypto.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(64),
    ),
    "crypto_library",
  )
  let session = signing_grant_fixture_require(
    begin_native_local_host_adoption(
      path + "/" + name + ".parent",
      name + ".host",
      path,
      account_file,
      "operator",
      crypto,
      configuration_files=[key_file, issuer_file, reviewer_file],
    ),
    "adoption",
  )
  let host = signing_grant_fixture_require(
    session.open_journal(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    ),
    "journal",
  )
  let reviewer = signing_grant_fixture_require(
    host.install_effect_reviewer(configuration_file=Some(reviewer_file)),
    "reviewer_selection",
  )
  let binding = signing_grant_fixture_require(
    host.acquire_signing_key_account(
      crypto,
      key_file,
      @checkpoint.EffectSet,
      reviewer=Some(reviewer),
    ),
    "key_account",
  )
  let key = signing_grant_fixture_require(
    binding.capture_signing_key_original(),
    "key_original",
  )
  let client_scope = signing_grant_fixture_require(
    host.authority_scope_cid("operator", "cli", crypto),
    "client_scope",
  )
  let epoch = signing_grant_fixture_require(
    host.epoch.issue_epoch(client_scope, true, 1000.0),
    "epoch",
  )
  let reference = signing_grant_fixture_require(
    prepare_native_client_submission_reference(
      epoch, "original-signing-submission",
    ),
    "reference",
  )
  let intent = signing_grant_fixture_require(
    @host.prepare_client_submitted_intent(
      "{\"kind\":\"program\",\"input\":" +
      preparation_values_document() +
      ",\"parameters\":null}",
      65536,
      8192,
      64,
    ),
    "intent",
  )
  let preparation = signing_grant_fixture_require(
    submitted_prepare(intent),
    "preparation",
  )
  guard preparation.preparation is Computation(prepared) else {
    fail("expected original Values preparation")
  }
  let (request, _, compiled, definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "original-signing-metadata-run",
    scope=client_scope,
  )
  signing_grant_fixture_require(
    host.journal.record_submitted_intent(
      host.epoch,
      reference,
      intent,
      client_scope,
      true,
      1001.0,
    ),
    "record_intent",
  )
  |> ignore
  signing_grant_fixture_require(
    host.journal.accept_submitted_run(
      host.epoch,
      reference,
      preparation,
      request,
      compiled,
      definition,
      client_scope,
      true,
      1002.0,
    ),
    "accept_run",
  )
  |> ignore
  let scope : @credential.LocalSigningCredentialScope = {
    account_configuration_cid: host.session.configuration.configuration_cid(),
    account_id: "operator",
    attempt_id: "original-signing-attempt",
    authority_scope_cid: key.account.scope,
    checkpoint_cid: "sha256:" + "1".repeat(64),
    checkpoint_id: "original-checkpoint-metadata",
    checkpoint_kind: @checkpoint.EffectSet,
    host_adoption_cid: host.adoption_cid,
    key_configuration_cid: key.account.file.content_cid,
    key_generation_cid: key.generation_cid(),
    key_id: "release-approver-2026",
    key_public_key_cid: key.public_key_cid(),
    preimage: "sha256:" + "2".repeat(64),
    principal: "reviewer",
    request_cid: @host.client_request_intent_cid(request),
    request_scope_cid: @host.client_request_scope_cid(request),
    run_definition_cid: @publication.publication_contract_identity(definition),
    run_invocation_cid: "sha256:" + "3".repeat(64),
    submission_scope_cid: reference.request_id,
    unit_definition_cid: "sha256:" + "4".repeat(64),
    purpose: @credential.ReviewerProof,
  }
  let grant = signing_grant_fixture_require(
    @credential.prepare_local_signing_credential_grant(
      "credential-authority-a",
      scope,
      @values.timestamp_epoch_milliseconds(expires_at).unwrap(),
      2,
    ),
    "grant_metadata",
  )
  let issuer = host.session.settings.files
    .iter()
    .find_first(file => file.name == issuer_file)
    .unwrap()
  let original = signing_grant_fixture_require(
    local_owned_grant_original(
      crypto,
      "original-signing-operation",
      request,
      issuer.content_cid,
      SigningGrant(grant),
    ),
    "grant_original",
  )
  local_grant_test_store(host, original)
  if retain_use {
    let grant_cid = @credential.local_signing_credential_grant_cid(grant)
    // Original credential journal fixture: no key read, signature or public
    // operational grant issuer is installed by these metadata storage steps.
    let ordinal = signing_grant_fixture_require(
      host.database.claim_ordinal(
        "native-credential-use:" + grant_cid,
        retained_use_id,
        2L,
      ),
      "fixture_original_claim",
    )
    let original_use = signing_grant_fixture_require(
      @credential.prepare_local_signing_credential_use(
        grant,
        retained_use_id,
        1003L,
        ordinal.to_int() - 1,
        false,
        scope,
      ),
      "fixture_original_use",
    )
    signing_grant_fixture_require(
      host.database.insert(
        "native-credential-use:" + grant_cid,
        retained_use_id,
        @utf8.encode(
          @credential.local_signing_credential_use_cid(original_use) +
          "\n" +
          @credential.local_signing_credential_use_json(original_use).unwrap(),
        ),
      ),
      "fixture_retain_use",
    )
    |> ignore
    signing_grant_fixture_require(
      host.database.insert(
        "native-credential-outcome:" + grant_cid,
        retained_use_id,
        b"unknown\n",
      ),
      "fixture_retain_outcome",
    )
    |> ignore
  }
  (host, key, original)
}

///|
test "Signing history Host uses Client RunRead and Reviewer resolve without issuer issue or credential read" {
  let (host, key, original) = signing_history_host_fixture("history-host-read")
  let before = run_record_body(
    host.journal.retained(original.request).unwrap().unwrap(),
  ).unwrap()
  let grant_row_key = local_grant_original_key(
    key.account.crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  let before_grant = host.database
    .read("client_local_grant_originals", grant_row_key)
    .unwrap()
  for operation in ["issue", "read"] {
    assert_false(
      host.authorize({
        principal: "operator",
        connection: "cli",
        resource: "credential/credential-authority-a",
        operation,
      })
      is Ok(@authorization.Allow(_)),
    )
  }
  for _ in 0..<2 {
    let read = signing_grant_fixture_require(
      key.lookup_signing_history(
        "operator",
        "cli",
        original.request,
        original.operation_id,
        "history-use",
      ),
      "authorized_history_read",
    )
    assert_eq(read.grant_cid(), local_original_grant_cid(original.grant))
    assert_true(read.observed_outcome() == @credential_resource.Unknown)
  }
  assert_eq(
    host.database.read("client_local_grant_originals", grant_row_key).unwrap().body,
    before_grant.body,
  )
  assert_eq(
    host.database.read("client_local_grant_originals", grant_row_key).unwrap().revision,
    0L,
  )
  assert_eq(
    run_record_body(host.journal.retained(original.request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
}

///|
test "Signing history Host reads expired grant history without enabling another use" {
  let (host, key, original) = signing_history_host_fixture(
    "history-host-expired",
    expires_at="1970-01-01T00:00:01.004Z",
  )
  let read = signing_grant_fixture_require(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    ),
    "expired_history_only",
  )
  guard original.grant is SigningGrant(grant) else {
    fail("expected saved Signing grant")
  }
  assert_eq(@credential.local_signing_credential_grant_limits(grant).1, 1004L)
  assert_true(
    @credential.validate_local_signing_credential_use_binding(
      read.original_use(),
      1004L,
      false,
      @credential.local_signing_credential_grant_scope(grant),
    )
    is Err(@credential.CredentialGrantInactive),
  )
  assert_eq(
    host.database
    .lookup_claim_ordinal(
      "native-credential-use:" + read.grant_cid(),
      "history-use",
    )
    .unwrap(),
    Some(1L),
  )
  host.close().unwrap()
}

///|
test "Signing history Host refuses missing current Client read and foreign principal connection" {
  let (host, key, original) = signing_history_host_fixture(
    "history-host-denied",
    client_read=false,
  )
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Err(HistoryOriginal(AuthorizationDenied)),
  )
  host.close().unwrap()
  let (host, key, original) = signing_history_host_fixture(
    "history-host-foreign-client",
  )
  for
    (principal, connection) in [
      ("other", "cli"),
      ("operator", "other"),
      ("reviewer", "review-cli"),
    ] {
    assert_true(
      key.lookup_signing_history(
        principal,
        connection,
        original.request,
        original.operation_id,
        "history-use",
      )
      is Err(HistoryOriginal(AuthorizationDenied)),
    )
  }
  host.close().unwrap()
}

///|
test "Signing history Host missing operation and use remain unavailable without new ordinal" {
  let (host, key, original) = signing_history_host_fixture(
    "history-host-missing",
    retain_use=false,
  )
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      "missing-operation",
      "history-use",
    )
    is Err(HistoryUnavailable),
  )
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Err(HistoryCredential(@credential_resource.Journal(@sqlite.NotFound))),
  )
  let scope = "native-credential-use:" +
    local_original_grant_cid(original.grant)
  assert_eq(
    host.database.lookup_claim_ordinal(scope, "history-use").unwrap(),
    None,
  )
  assert_true(host.database.read(scope, "history-use") is Err(@sqlite.NotFound))
  host.close().unwrap()
}

///|
test "Signing history Host lost original reservation is rolled back and never repaired" {
  let (host, key, original) = signing_history_host_fixture(
    "history-host-reservation",
  )
  host.database
  .release_capacity(
    "client_local_grant_originals",
    local_original_grant_reservation_scope(original),
    65536L,
    1L,
  )
  .unwrap()
  |> ignore
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Err(HistoryOriginal(CustodyLost)),
  )
  let usage = host.database
    .capacity_usage("client_local_grant_originals")
    .unwrap()
  assert_eq(usage.reserved_objects, 0L)
  assert_eq(usage.reserved_bytes, 0L)
  assert_eq(
    host.database
    .lookup_claim_ordinal(
      "native-credential-use:" + local_original_grant_cid(original.grant),
      "history-use",
    )
    .unwrap(),
    Some(1L),
  )
  host.close().unwrap()
}

///|
test "Signing history Host key replacement and closed original cannot disclose saved outcome" {
  let name = "history-host-generation"
  let (host, key, original) = signing_history_host_fixture(name)
  let file = name + ".descriptor"
  let root = host.session.source_root
  root
  .reclaim_generation(file, root.inspect_generation(file).unwrap().unwrap())
  .unwrap()
  let writer = root.create_writer(name + ".replacement.stage", 8192L).unwrap()
  writer.append(b"synthetic-file-projection-only").unwrap()
  writer.seal(file).unwrap() |> ignore
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Err(_),
  )
  host.close().unwrap()
  assert_true(
    key.lookup_signing_history(
      "operator",
      "cli",
      original.request,
      original.operation_id,
      "history-use",
    )
    is Err(_),
  )
}

///|
test "Signing history Host lost read transaction ACK stays typed Unknown without another use" {
  let (host, key, original) = signing_history_host_fixture(
    "history-host-unknown",
  )
  client_test_fail_commit_reply(host.database, 1)
  let observed = key.lookup_signing_history(
    "operator",
    "cli",
    original.request,
    original.operation_id,
    "history-use",
  )
  assert_true(observed is Err(HistoryKey(SigningJournal(TransactionUnknown))))
  // No follow-up read or new attempt is made through the fenced original.
  assert_true(host.database.transaction_fenced())
  host.close().unwrap()
}
