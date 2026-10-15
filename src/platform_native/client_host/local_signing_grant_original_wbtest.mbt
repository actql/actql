///|
// Keep fixture failures in the Native test summary. Never print original rows,
// key material, configuration bodies or diagnostic stacks.
fn[T, E] signing_grant_fixture_require(
  value : Result[T, E],
  phase : String,
) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("Signing fixture phase=" + phase + " issue=Refused")
  }
}

///|
// These are real private SQLite/Host metadata custody fixtures, never private
// keys, an operational signing grant, paired capture or signature acceptance.
fn signing_grant_original_fixture(
  name : String,
) -> (
  NativeLocalHostConnection,
  NativeLocalSigningKeyOriginal,
  NativeLocalGrantOriginal,
) raise {
  let key_file = name + ".key.json"
  let descriptor = name + ".descriptor"
  let issuer_file = name + ".issuer.json"
  let account_file = name + ".account.json"
  signing_original_write(
    key_file,
    @utf8.encode(
      signing_original_configuration(descriptor, signing_original_public_a),
    ),
  )
  signing_original_write(descriptor, b"synthetic-file-projection-only")
  signing_original_write(issuer_file, @utf8.encode(local_issuer_fixture_wire))
  let account = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"a-sign\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"host-signer\"]},\"connection\":{\"any_of\":[\"host-cli\"]},\"resource\":{\"any_of\":[\"key/host-attestation-2026\"]},\"operation\":{\"any_of\":[\"sign\"]},\"exclusions\":[]},{\"entry_id\":\"b-issu\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"credential/credential-authority-a\"]},\"operation\":{\"any_of\":[\"issue\"]},\"exclusions\":[]}] }"
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
      configuration_files=[key_file, issuer_file],
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
  let binding = signing_grant_fixture_require(
    host.acquire_signing_key_account(crypto, key_file, @checkpoint.EffectSet),
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
    key_id: "host-attestation-2026",
    key_public_key_cid: key.public_key_cid(),
    preimage: "sha256:" + "2".repeat(64),
    principal: "host-signer",
    request_cid: @host.client_request_intent_cid(request),
    request_scope_cid: @host.client_request_scope_cid(request),
    run_definition_cid: @publication.publication_contract_identity(definition),
    run_invocation_cid: "sha256:" + "3".repeat(64),
    submission_scope_cid: reference.request_id,
    unit_definition_cid: "sha256:" + "4".repeat(64),
    purpose: @credential.HostAttestation,
  }
  let grant = signing_grant_fixture_require(
    @credential.prepare_local_signing_credential_grant(
      "credential-authority-a",
      scope,
      @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
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
  (host, key, original)
}

///|
fn signing_grant_original_roundtrip(
  original : NativeLocalGrantOriginal,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  let crypto = epoch_test_crypto()
  let key = local_grant_original_key(
    crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  read_local_grant_original(crypto, {
    key,
    body: local_grant_original_packet(original).unwrap(),
    revision: 0L,
  })
}

///|
test "Signing original packet preserves its own purpose and distinct Client signer issuer subjects" {
  let (host, _, original) = signing_grant_original_fixture(
    "signing-grant-packet",
  )
  let restored = signing_grant_fixture_require(
    signing_grant_original_roundtrip(original),
    "packet_roundtrip",
  )
  assert_eq(restored.intent, original.intent)
  assert_eq(
    local_grant_original_packet(restored).unwrap(),
    local_grant_original_packet(original).unwrap(),
  )
  guard restored.grant is SigningGrant(grant) else {
    fail("Signing restored as HTTP")
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  assert_eq(
    scope.submission_scope_cid,
    @host.client_request_caller_id(original.request),
  )
  assert_true(scope.submission_scope_cid != scope.request_scope_cid)
  assert_true(
    scope.authority_scope_cid !=
    @host.client_request_authority_scope_cid(original.request),
  )
  assert_eq(
    local_original_grant_reservation_scope(restored),
    scope.request_scope_cid,
  )
  let packet = local_grant_packet_object(
    local_grant_original_packet(original).unwrap(),
  ).unwrap()
  assert_eq(epoch_text(packet, "signing_purpose"), Some("host_attestation"))
  assert_true(@decode.lookup(packet, "preparation_fence") is None)
  host.close().unwrap()
}

///|
test "Signing packet refuses missing changed null or mixed-purpose metadata without HTTP fallback" {
  let (host, _, original) = signing_grant_original_fixture("signing-grant-tags")
  let crypto = epoch_test_crypto()
  let key = local_grant_original_key(
    crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  let wire = @utf8.decode(local_grant_original_packet(original).unwrap()) catch {
    _ => fail("expected packet UTF8")
  }
  for
    body in [
      wire.replace_all(old=",\"signing_purpose\":\"host_attestation\"", new=""),
      wire.replace_all(
        old="\"signing_purpose\":\"host_attestation\"",
        new="\"signing_purpose\":\"reviewer_proof\"",
      ),
      wire.replace_all(
        old="\"signing_purpose\":\"host_attestation\"",
        new="\"signing_purpose\":null",
      ),
      wire.replace_all(
        old="\"signing_purpose\":\"host_attestation\"",
        new="\"preparation_fence\":\"{}\",\"signing_purpose\":\"host_attestation\"",
      ),
    ] {
    assert_true(
      read_local_grant_original(crypto, {
        key,
        body: @utf8.encode(body),
        revision: 0L,
      })
      is Err(CustodyLost),
    )
  }
  host.close().unwrap()
}

///|
test "Signing original reader rejects changed intent logical scope or copied Submission identity" {
  let (host, _, original) = signing_grant_original_fixture(
    "signing-grant-subject",
  )
  guard original.grant is SigningGrant(grant) else { fail("expected Signing") }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  for
    changed in [
      { ..scope, request_cid: "sha256:" + "5".repeat(64), },
      { ..scope, request_scope_cid: "sha256:" + "6".repeat(64), },
      { ..scope, submission_scope_cid: "sha256:" + "7".repeat(64), },
    ] {
    let grant = @credential.prepare_local_signing_credential_grant(
      "credential-authority-a",
      changed,
      @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
      2,
    ).unwrap()
    let changed = local_owned_grant_original(
      epoch_test_crypto(),
      original.operation_id,
      original.request,
      original.issuer_selection_cid,
      SigningGrant(grant),
    ).unwrap()
    assert_true(signing_grant_original_roundtrip(changed) is Err(CustodyLost))
  }
  host.close().unwrap()
}

///|
test "Signing custody uses the same original reservation and never acquires issuer signing authority" {
  let (host, key, original) = signing_grant_original_fixture(
    "signing-grant-custody",
  )
  let before = run_record_body(
    host.journal.retained(original.request).unwrap().unwrap(),
  ).unwrap()
  local_grant_test_store(host, original)
  let facts = host.journal
    .transaction(() => {
      let (count, _, runs) = host
        .local_grant_custody(epoch_test_crypto())
        .unwrap()
      let saved = host
        .lookup_local_grant_original_locked(epoch_test_crypto(), original)
        .unwrap()
        .unwrap()
      Ok(
        (
          count,
          runs.length(),
          runs.get(local_original_grant_reservation_scope(original)) is Some(_),
          saved.intent,
        ),
      )
    })
    .unwrap()
  assert_eq(facts.0, 1)
  assert_eq(facts.1, 1)
  assert_true(facts.2)
  assert_eq(facts.3, original.intent)
  let issuer_file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  let issuer = host
    .acquire_credential_issuer(
      epoch_test_crypto(),
      issuer_file.name,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  assert_true(
    issuer.lookup_grant_original(original) is Err(AuthorizationDenied),
  )
  assert_true(
    host.journal.transaction(() => {
      issuer.append_grant_original_locked(original, () => Ok(()))
    })
    is Err(AuthorizationDenied),
  )
  assert_true(key.require_current_key() is Ok(_))
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  assert_eq(
    run_record_body(host.journal.retained(original.request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
}

///|
test "Signing custody refuses foreign Run or key generation despite a valid new grant CID" {
  let (host, _, original) = signing_grant_original_fixture(
    "signing-grant-foreign",
  )
  guard original.grant is SigningGrant(grant) else { fail("expected Signing") }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let refused = host.journal
    .transaction(() => {
      let observations = []
      for
        changed in [
          { ..scope, run_definition_cid: "sha256:" + "5".repeat(64), },
          { ..scope, key_generation_cid: "sha256:" + "6".repeat(64), },
          { ..scope, key_public_key_cid: "sha256:" + "7".repeat(64), },
          {
            ..scope,
            authority_scope_cid: @host.client_request_authority_scope_cid(
              original.request,
            ),
          },
        ] {
        let grant = @credential.prepare_local_signing_credential_grant(
          "credential-authority-a",
          changed,
          @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
          2,
        ).unwrap()
        observations.push(
          host.check_signing_grant_original_locked(
            grant,
            original.request,
            scope.run_definition_cid,
          )
          is Err(CustodyLost),
        )
      }
      Ok(observations)
    })
    .unwrap()
  assert_eq(refused.length(), 4)
  assert_true(refused.all(value => value))
  host.close().unwrap()
}

///|
test "Signing history original absence is unresolved and lost reservation is never repaired" {
  let (host, _, original) = signing_grant_original_fixture(
    "signing-grant-missing",
  )
  let missing = host.journal
    .transaction(() => {
      host
      .lookup_local_grant_original_locked(epoch_test_crypto(), original)
      .map(value => value is None)
    })
    .unwrap()
  assert_true(missing)
  local_grant_test_store(host, original)
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
    host.journal.transaction(() => {
      host
      .lookup_local_grant_original_locked(epoch_test_crypto(), original)
      .map(_ => ())
    })
    is Err(CustodyLost),
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  host.close().unwrap()
}
