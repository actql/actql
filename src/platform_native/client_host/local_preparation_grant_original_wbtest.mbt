///|
// Storage-only fixture, not a started checked Effect Work or Provider permit.
// Production append separately requires its unforgeable original Work fence.
fn local_preparation_storage_original(
  host : NativeLocalHostConnection,
  mutation_original : NativeLocalGrantOriginal,
  operation_id : String,
) -> NativeLocalGrantOriginal {
  let scope = local_original_resume_grant_scope(mutation_original.grant)
  let fence = @credential.prepare_local_preparation_fence_identity({
    client_request_intent_cid: @host.client_request_intent_cid(
      mutation_original.request,
    ),
    client_request_scope_cid: @host.client_request_scope_cid(
      mutation_original.request,
    ),
    operation_occurrence_cid: scope.operation_occurrence_cid,
    run_invocation_cid: scope.run_invocation_cid,
    unit_definition_cid: scope.unit_definition_cid,
  }).unwrap()
  let preparation : @credential.LocalPreparationCredentialScope = {
    account_configuration_cid: scope.account_configuration_cid,
    account_id: scope.account_id,
    attempt_id: "observe-original",
    authority_scope_cid: scope.authority_scope_cid,
    connector_registration: scope.connector_registration,
    connector_revision: scope.connector_revision,
    preparation_fence: fence,
    host_adoption_cid: host.adoption_cid,
    operation: "salesforce:record:observe",
    operation_occurrence_cid: scope.operation_occurrence_cid,
    principal: scope.principal,
    request_body_cid: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    request_cid: "sha256:" + "9".repeat(64),
    request_method: "GET",
    request_path: scope.request_path,
    resource_origin: scope.resource_origin,
    run_invocation_cid: scope.run_invocation_cid,
    submission_scope_cid: scope.submission_scope_cid,
    unit_definition_cid: scope.unit_definition_cid,
  }
  let grant = @credential.prepare_local_preparation_credential_grant(
    "credential-authority-a",
    preparation,
    @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
    2,
  ).unwrap()
  local_preparation_grant_original(
    epoch_test_crypto(),
    operation_id,
    mutation_original.request,
    mutation_original.issuer_selection_cid,
    grant,
  ).unwrap()
}

///|
test "Native preparation grant custody retains the full original fence in the same bounded journal" {
  let (host, _, mutation_original) = local_grant_storage_fixture(
    "preparation-grant-packet",
  )
  let original = local_preparation_storage_original(
    host, mutation_original, "explicit-observe",
  )
  let crypto = epoch_test_crypto()
  let packet = local_grant_original_packet(original).unwrap()
  let key = local_grant_original_key(
    crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  let restored = read_local_grant_original(crypto, {
    key,
    body: packet,
    revision: 0L,
  }).unwrap()
  assert_eq(restored.intent, original.intent)
  assert_eq(local_grant_original_packet(restored).unwrap(), packet)
  guard (original.grant, restored.grant)
    is (PreparationGrant(expected), PreparationGrant(actual)) else {
    fail("preparation cannot be restored as Resume")
  }
  assert_eq(
    @credential.local_preparation_credential_grant_scope(actual),
    @credential.local_preparation_credential_grant_scope(expected),
  )
  // Old packet and intent bytes still contain only their original grant/intent.
  let old_packet = local_grant_original_packet(mutation_original).unwrap()
  let exact_old = local_read_evidence_object(
    old_packet,
    ["grant", "intent"],
    49152,
  ).unwrap()
  assert_eq(
    epoch_text(exact_old, "grant"),
    Some(local_original_grant_json(mutation_original.grant).unwrap()),
  )
  assert_true(
    read_local_grant_original(crypto, { key, body: old_packet, revision: 0L, })
    is Err(CustodyLost),
  )
  // Both records share one existing per-Run reservation and issuance count.
  local_grant_test_store(host, mutation_original)
  local_grant_test_store(host, original)
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    2L,
  )
  // Obtain the actual selected filename rather than presume the fixture label.
  let file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  let binding = host
    .acquire_credential_issuer(
      crypto,
      file.name,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  let before = host.journal.retained(original.request).unwrap().unwrap().revision
  for _ in 0..<3 {
    let saved = binding.lookup_grant_original(original).unwrap().unwrap()
    assert_eq(local_grant_original_packet(saved).unwrap(), packet)
  }
  assert_eq(
    host.journal.retained(original.request).unwrap().unwrap().revision,
    before,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    2L,
  )
  host.close().unwrap()
}

///|
// Exercise the shared storage transaction only. This test callback is not the
// production preparation authority: that private entry requires the live Work.
test "Native preparation original append replay preserves its exact allowance and reservation" {
  let (host, _, mutation_original) = local_grant_storage_fixture(
    "preparation-append-replay",
  )
  let original = local_preparation_storage_original(
    host, mutation_original, "explicit-observe",
  )
  let crypto = epoch_test_crypto()
  let file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  let binding = host
    .acquire_credential_issuer(
      crypto,
      file.name,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  let before = host.journal.retained(original.request).unwrap().unwrap().revision
  for _ in 0..<3 {
    host.journal
    .transaction(() => {
      binding.append_grant_original_locked(original, () => Ok(()))
    })
    .unwrap()
    assert_eq(
      host.database.read("client_local_grant_custody", "issued").unwrap().revision,
      1L,
    )
    assert_eq(
      host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
      65536L,
    )
    let saved = binding.lookup_grant_original(original).unwrap().unwrap()
    assert_eq(
      local_grant_original_packet(saved).unwrap(),
      local_grant_original_packet(original).unwrap(),
    )
  }
  let changed = local_preparation_storage_original(
    host, mutation_original, "different-explicit-operation",
  )
  assert_true(
    host.journal.transaction(() => {
      binding.append_grant_original_locked(changed, () => Ok(()))
    })
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.journal.retained(original.request).unwrap().unwrap().revision,
    before,
  )
  host.close().unwrap()
}

///|
test "Native preparation append refuses loss of current authority without retaining a fresh reservation" {
  let (host, _, mutation_original) = local_grant_storage_fixture(
    "preparation-append-current",
  )
  let original = local_preparation_storage_original(
    host, mutation_original, "explicit-observe",
  )
  let crypto = epoch_test_crypto()
  let file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  let binding = host
    .acquire_credential_issuer(
      crypto,
      file.name,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  assert_true(
    host.journal.transaction(() => {
      binding.append_grant_original_locked(original, () => {
        Err(AuthorizationDenied)
      })
    })
    is Err(AuthorizationDenied),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    0L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_true(binding.lookup_grant_original(original) is Ok(None))
  host.journal
  .transaction(() => {
    binding.append_grant_original_locked(original, () => Ok(()))
  })
  .unwrap()
  // Even an exact replay must pass the final current check; refusing it does
  // not delete the original or replace its expiry, allowance or reservation.
  assert_true(
    host.journal.transaction(() => {
      binding.append_grant_original_locked(original, () => {
        Err(AuthorizationDenied)
      })
    })
    is Err(AuthorizationDenied),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  assert_eq(
    local_grant_original_packet(
      binding.lookup_grant_original(original).unwrap().unwrap(),
    ).unwrap(),
    local_grant_original_packet(original).unwrap(),
  )
  host.close().unwrap()
}

///|
test "Native preparation append refuses missing exact reservation without repairing custody" {
  let (host, _, mutation_original) = local_grant_storage_fixture(
    "preparation-append-custody",
  )
  let original = local_preparation_storage_original(
    host, mutation_original, "explicit-observe",
  )
  let crypto = epoch_test_crypto()
  let file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  let binding = host
    .acquire_credential_issuer(
      crypto,
      file.name,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  host.journal
  .transaction(() => {
    binding.append_grant_original_locked(original, () => Ok(()))
  })
  .unwrap()
  host.database
  .release_capacity(
    "client_local_grant_originals",
    @host.client_request_scope_cid(original.request),
    65536L,
    1L,
  )
  .unwrap()
  |> ignore
  assert_true(
    host.journal.transaction(() => {
      binding.append_grant_original_locked(original, () => Ok(()))
    })
    is Err(CustodyLost),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_true(binding.lookup_grant_original(original) is Err(CustodyLost))
  host.close().unwrap()
}

///|
test "Native preparation grant packet refuses missing altered foreign and rewritten original fence" {
  let (host, _, mutation_original) = local_grant_storage_fixture(
    "preparation-grant-missing",
  )
  let original = local_preparation_storage_original(
    host, mutation_original, "explicit-observe",
  )
  let crypto = epoch_test_crypto()
  let packet = local_grant_original_packet(original).unwrap()
  let key = local_grant_original_key(
    crypto,
    original.request,
    original.operation_id,
  ).unwrap()
  let object = local_grant_packet_object(packet).unwrap()
  let grant_wire = epoch_text(object, "grant").unwrap()
  let intent_wire = epoch_text(object, "intent").unwrap()
  let fence_wire = epoch_text(object, "preparation_fence").unwrap()
  for
    fields in [
      [("grant", grant_wire), ("intent", intent_wire)],
      [
        ("grant", grant_wire),
        ("intent", intent_wire),
        ("preparation_fence", fence_wire + " "),
      ],
      [
        ("grant", grant_wire),
        ("intent", intent_wire),
        (
          "preparation_fence",
          fence_wire.replace_all(old="sha256:", new="SHA256:"),
        ),
      ],
      [
        ("grant", local_original_grant_json(mutation_original.grant).unwrap()),
        ("intent", intent_wire),
        ("preparation_fence", fence_wire),
      ],
      [
        ("grant", grant_wire),
        ("intent", intent_wire),
        ("preparation_fence", fence_wire),
        ("extra", "value"),
      ],
    ] {
    let writer = @encode.writer(49152, 16, 2)
    @encode.begin_object(writer)
    for (name, value) in fields {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    let body = @utf8.encode(@encode.finish(writer))
    assert_true(
      read_local_grant_original(crypto, { key, body, revision: 0L, })
      is Err(CustodyLost),
    )
  }
  assert_true(
    read_local_grant_original(crypto, { key, body: packet, revision: 1L, })
    is Err(CustodyLost),
  )
  host.close().unwrap()
}
