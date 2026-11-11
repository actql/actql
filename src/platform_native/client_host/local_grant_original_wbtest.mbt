///|
// These are finite physical custody fixture definitions, compile-only until
// matching Native execution. They exercise the private storage step, never
// assert checked Provider authorization, approval or a public grant issuance.
fn local_grant_storage_fixture(
  name : String,
  account_body? : Bytes = local_issuer_fixture_account,
  state_parent? : String? = None,
) -> (
  NativeLocalHostConnection,
  NativeLocalCredentialIssuerBinding,
  NativeLocalGrantOriginal,
) {
  let (host, file) = local_issuer_fixture(name, account_body~, state_parent~)
  let original = local_grant_test_original(host, file)
  let binding = host
    .acquire_credential_issuer(
      epoch_test_crypto(),
      file,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  (host, binding, original)
}

///|
// Fixture-only identity/storage setup: constructing an original is not an
// issuer decision, checked Work fence or operational grant acknowledgement.
fn local_grant_test_original(
  host : NativeLocalHostConnection,
  file : String,
) -> NativeLocalGrantOriginal {
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "original-submission",
    "original-run",
    scope~,
  )
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let selected = host.session.settings.files
    .iter()
    .find_first(value => value.name == file)
    .unwrap()
  let grant = @credential.prepare_local_credential_grant(
    "credential-authority-a",
    {
      account_configuration_cid: host.session.configuration.configuration_cid(),
      account_id: "operator",
      attempt_id: "original-use",
      authority_scope_cid: scope,
      connector_registration: "salesforce",
      connector_revision: "fixture-v1",
      fence_claimant: "host-original",
      fence_generation: 1L,
      fence_intent_cid: "sha256:" + "b".repeat(64),
      host_adoption_cid: host.adoption_cid,
      operation: "salesforce:record:patch",
      operation_occurrence_cid: "sha256:" + "c".repeat(64),
      principal: "operator",
      request_body_cid: "sha256:6399fe49a070085db566de0c03e6098e3562ddf9348d1f81bca23ab0658c8e31",
      request_cid: "sha256:" + "d".repeat(64),
      request_method: "PATCH",
      request_path: "/services/data/v65.0/sobjects/Account/001000000000001AAA",
      resource_origin: "https://example.test",
      run_invocation_cid: "sha256:" + "e".repeat(64),
      submission_scope_cid: @host.client_request_scope_cid(request),
      unit_definition_cid: "sha256:" + "f".repeat(64),
    },
    @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
    2,
  ).unwrap()
  let original = local_grant_original(
    crypto,
    "issue-original",
    request,
    selected.content_cid,
    grant,
  ).unwrap()
  original
}

///|
// Stand-alone storage observation; not the production append's claim checks.
fn local_grant_test_store(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
) -> Unit {
  host.journal
  .transaction(() => {
    let scope = @host.client_request_scope_cid(original.request)
    host.database
    .reserve_capacity_in_transaction(
      "client_local_grant_originals", scope, 65536L, 1L, 524288L, 8L,
    )
    .unwrap()
    |> ignore
    let key = local_grant_original_key(
      epoch_test_crypto(),
      original.request,
      original.operation_id,
    ).unwrap()
    let packet = local_grant_original_packet(original).unwrap()
    host.database.insert("client_local_grant_originals", key, packet).unwrap()
    |> ignore
    let issued = host.database
      .read("client_local_grant_custody", "issued")
      .unwrap()
    host.database
    .compare_exchange(
      "client_local_grant_custody",
      "issued",
      issued.revision,
      @utf8.encode((issued.revision + 1L).to_string()),
    )
    .unwrap()
    |> ignore
    Ok(())
  })
  .unwrap()
}

///|
test "Native grant original keys bind explicit operation IDs while divergent input changes the immutable intent" {
  let (host, _, original) = local_grant_storage_fixture("local-grant-intent")
  let crypto = epoch_test_crypto()
  let key = local_grant_original_key(
    crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  let scope = local_original_resume_grant_scope(original.grant)
  let changed = @credential.prepare_local_credential_grant(
    "credential-authority-a",
    {
      ..scope,
      request_path: "/services/data/v65.0/sobjects/Account/002000000000001AAA",
    },
    @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
    2,
  ).unwrap()
  let divergent = local_grant_original(
    crypto,
    original.operation_id,
    original.request,
    original.issuer_selection_cid,
    changed,
  ).unwrap()
  assert_eq(
    local_grant_original_key(crypto, divergent.request, divergent.operation_id).unwrap(),
    key,
  )
  assert_false(original.operation_cid == divergent.operation_cid)
  assert_false(original.intent == divergent.intent)
  assert_false(
    local_grant_original_key(
      crypto,
      original.request,
      "explicit-other-operation",
    ).unwrap() ==
    key,
  )
  let packet = local_grant_original_packet(original).unwrap()
  let decoded = read_local_grant_original(crypto, {
    key,
    body: packet,
    revision: 0L,
  }).unwrap()
  assert_eq(decoded.operation_id, "issue-original")
  assert_eq(
    local_original_resume_grant_scope(decoded.grant).request_body_cid,
    "sha256:6399fe49a070085db566de0c03e6098e3562ddf9348d1f81bca23ab0658c8e31",
  )
  assert_true(
    read_local_grant_original(crypto, { key, body: packet, revision: 1L, })
    is Err(CustodyLost),
  )
  assert_true(
    read_local_grant_original(crypto, {
      key: "sha256:" + "0".repeat(64),
      body: packet,
      revision: 0L,
    })
    is Err(CustodyLost),
  )
  host.close().unwrap()
}

///|
test "Native original grant lookup returns the exact custody without changing adoption Run or reservations" {
  let (host, binding, original) = local_grant_storage_fixture(
    "local-grant-lookup",
  )
  guard host.journal.lookup(original.request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  let adoption = host.adoption_cid
  assert_true(binding.lookup_grant_original(original) is Ok(None))
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  local_grant_test_store(host, original)
  for _ in 0..<3 {
    let restored = binding.lookup_grant_original(original).unwrap().unwrap()
    assert_eq(restored.intent, original.intent)
    assert_eq(
      local_original_grant_json(restored.grant),
      local_original_grant_json(original.grant),
    )
  }
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  guard host.journal.lookup(original.request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  assert_eq(host.adoption_cid, adoption)
  host.close().unwrap()
}

///|
test "Native grant lookup refuses missing original or capacity custody and never repairs it" {
  for
    mode in [
      "packet", "reservation", "foreign-reservation", "witness", "corrupt",
    ] {
    let (host, binding, original) = local_grant_storage_fixture(
      "local-grant-loss-" + mode,
    )
    local_grant_test_store(host, original)
    let key = local_grant_original_key(
      epoch_test_crypto(),
      original.request,
      original.operation_id,
    ).unwrap()
    if mode == "packet" {
      let table_bytes = @utf8.encode("client_local_grant_originals")
      let key_bytes = @utf8.encode(key)
      assert_true(
        submitted_test_remove_record(
          host.database,
          table_bytes,
          table_bytes.length(),
          key_bytes,
          key_bytes.length(),
        ),
      )
    } else if mode == "reservation" || mode == "foreign-reservation" {
      host.database
      .release_capacity(
        "client_local_grant_originals",
        @host.client_request_scope_cid(original.request),
        65536L,
        1L,
      )
      .unwrap()
      |> ignore
      if mode == "foreign-reservation" {
        host.database
        .reserve_capacity(
          "client_local_grant_originals", "foreign-run", 65536L, 1L, 524288L, 8L,
        )
        .unwrap()
        |> ignore
      }
    } else if mode == "witness" {
      let table_bytes = @utf8.encode("client_local_grant_custody")
      assert_true(
        submitted_test_remove_record(
          host.database,
          table_bytes,
          table_bytes.length(),
          b"issued",
          6,
        ),
      )
    } else {
      host.database
      .compare_exchange("client_local_grant_originals", key, 0L, b"{}")
      .unwrap()
      |> ignore
    }
    assert_true(binding.lookup_grant_original(original) is Err(CustodyLost))
    assert_true(binding.lookup_grant_original(original) is Err(CustodyLost))
    if mode == "reservation" {
      assert_eq(
        host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
        0L,
      )
    }
    if mode == "foreign-reservation" {
      // The aggregate matches, but the original reservation is still missing.
      // Refused lookup must roll back its fresh probe and preserve that loss.
      assert_eq(
        host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_objects,
        1L,
      )
      assert_true(
        host.database
        .reserve_capacity(
          "client_local_grant_originals",
          @host.client_request_scope_cid(original.request),
          65536L,
          1L,
          524288L,
          8L,
        )
        .unwrap(),
      )
    }
    if mode == "packet" {
      assert_true(
        host.database.read("client_local_grant_originals", key)
        is Err(@sqlite.NotFound),
      )
    }
    host.close().unwrap()
  }
}

///|
test "Native grant original append requires the actual retained resume fence instead of fixture scope strings" {
  let (host, binding, original) = local_grant_storage_fixture(
    "local-grant-no-resume",
  )
  // Owning-module hostile material: a constructed claim is not present in the
  // journal. This must refuse before packet/reservation/Run changes occur.
  let scope = local_original_resume_grant_scope(original.grant)
  let fabricated : NativeClientEffectResumeClaim = {
    journal: host.journal,
    request: original.request,
    checkpoint_cid: "sha256:" + "1".repeat(64),
    resolution_cid: "sha256:" + "2".repeat(64),
    intent_id: scope.fence_intent_cid,
    claim: {
      claimant: scope.fence_claimant,
      generation: scope.fence_generation,
    },
    approval: @checkpoint.resumed_approval(
      @env.get_env_var("ACTQL_TEST_CLIENT_APPROVE_VERIFIED_WIRE").unwrap(),
      native_checkpoint_limits(),
    ).unwrap(),
  }
  assert_true(
    binding.retain_grant_original(original, fabricated)
    is Err(AuthorizationDenied),
  )
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"0",
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  host.close().unwrap()
}

///|
// Test-only explicit unwrap of the old typed branch. It is never a fake
// positive-generation scope for preparation or a production fallback.
fn local_original_resume_grant_scope(
  grant : NativeLocalOriginalGrant,
) -> @credential.LocalCredentialScope {
  match grant {
    ResumeGrant(value) => @credential.local_credential_grant_scope(value)
    PreparationGrant(_) | SigningGrant(_) =>
      abort("test expected an original Resume grant")
  }
}
