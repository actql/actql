///|
// Real initialized Host/Store/key/SQLite and original retained Submission/Run.
// The subject metadata is synthetic: these are private storage-phase probes,
// not paired-capture, current RunRead, public approval or signing acceptance.
fn initial_issue_storage_fixture(
  name : String,
) -> (
  NativeLocalInitialReviewerSigningKey,
  @host.ClientRequestIdentity,
  @credential.LocalSigningCredentialScope,
) raise {
  let (host, file) = initial_reviewer_fixture(name)
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(original, installed)
    .unwrap()
  let authority = key.fields.authority_scope_cid
  let epoch = host.epoch.issue_epoch(authority, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "initial-issue-storage-only",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document() +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = submitted_prepare(intent).unwrap()
  guard preparation.preparation is Computation(prepared) else {
    fail("expected original Values")
  }
  let (request, _, compiled, definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "initial-storage-run",
    scope=authority,
  )
  host.journal
  .record_submitted_intent(
    host.epoch,
    reference,
    intent,
    authority,
    true,
    1001.0,
  )
  .unwrap()
  |> ignore
  host.journal
  .accept_submitted_run(
    host.epoch,
    reference,
    preparation,
    request,
    compiled,
    definition,
    authority,
    true,
    1002.0,
  )
  .unwrap()
  |> ignore
  let scope = {
    ..initial_proof_key_candidate(key),
    request_cid: @host.client_request_intent_cid(request),
    request_scope_cid: @host.client_request_scope_cid(request),
    submission_scope_cid: reference.request_id,
    run_definition_cid: @publication.publication_contract_identity(definition),
  }
  (key, request, scope)
}

///|
// Preserve the exact credential error while the existing Journal owns rollback
// and COMMITUnknown. A storage result is not exposed as a physical-sign permit.
fn initial_issue_storage_transaction(
  key : NativeLocalInitialReviewerSigningKey,
  request : @host.ClientRequestIdentity,
  scope : @credential.LocalSigningCredentialScope,
  sample : () -> Int64,
  operation? : String = "initial-storage-operation",
  bound? : Int64? = None,
  after? : () -> Result[Unit, NativeClientRunJournalIssue] = () => Ok(()),
) -> Result[
  NativeLocalInitialSigningStorageResult,
  NativeLocalInitialSigningStorageIssue,
] {
  let primary : Ref[NativeLocalInitialSigningStorageIssue?] = Ref(None)
  let result = key.original.host.journal.transaction(() => {
    let stored = match
      local_initial_signing_issue_storage_locked(
        key,
        request,
        scope,
        operation,
        bound,
        sample,
        () => key.require_current().map_err(_ => AuthorizationDenied),
      ) {
      Ok(value) => value
      Err(issue) => {
        primary.val = Some(issue)
        return Err(CustodyLost)
      }
    }
    after().map(_ => stored)
  })
  match result {
    Ok(value) => Ok(value)
    Err(CustodyLost) =>
      Err(primary.val.unwrap_or(InitialStorageJournal(CustodyLost)))
    Err(issue) => Err(InitialStorageJournal(issue))
  }
}

///|
fn initial_issue_storage_original(
  result : NativeLocalInitialSigningStorageResult,
) -> NativeLocalGrantOriginal {
  match result {
    InitialStorageClaim(original, _) | InitialStorageHistory(original, _) =>
      original
  }
}

///|
test "initial issue storage commits original expiry and exact first use then reads history without sampling" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-atomic",
  )
  let host = key.original.host
  let samples = Ref(0)
  let first = initial_issue_storage_transaction(
    key,
    request,
    scope,
    () => {
      samples.val += 1
      10000L
    },
    bound=Some(20000L),
  ).unwrap()
  let fresh = first is InitialStorageClaim(_, _)
  guard first is InitialStorageClaim(_, claimed_use) else {
    fail("expected original claim")
  }
  let claimed_use_cid = @credential.local_signing_credential_use_cid(
    claimed_use,
  )
  let original = initial_issue_storage_original(first)
  guard original.grant is SigningGrant(grant) else { fail("expected Signing") }
  let limits = @credential.local_signing_credential_grant_limits(grant)
  let rowkey = local_grant_original_key(
    host.epoch.crypto,
    request,
    original.operation_id,
  ).unwrap()
  let row = host.database.read("client_local_grant_originals", rowkey).unwrap()
  let exact_packet = local_grant_original_packet(original).unwrap() == row.body
  let second = initial_issue_storage_transaction(
    key,
    request,
    scope,
    () => {
      samples.val += 1
      900000L
    },
    bound=Some(20000L),
  ).unwrap()
  let history_only = second is InitialStorageHistory(_, _)
  guard second is InitialStorageHistory(_, historical) else {
    fail("expected original history")
  }
  assert_eq(
    @credential.local_signing_credential_use_cid(historical.original_use()),
    claimed_use_cid,
  )
  assert_eq(historical.grant_cid(), local_original_grant_cid(original.grant))
  let cid_exact = local_original_grant_cid(
      initial_issue_storage_original(second).grant,
    ) ==
    local_original_grant_cid(original.grant)
  let (count, _, _) = host.journal
    .transaction(() => host.local_grant_custody(host.epoch.crypto))
    .unwrap()
  host.close().unwrap()
  assert_true(fresh && exact_packet && history_only && cid_exact)
  assert_eq(samples.val, 1)
  assert_eq(limits, (1, 20000L))
  assert_eq(count, 1)
}

///|
test "initial issue current refusal after claim rolls back grant use count and clock together" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-rollback",
  )
  let host = key.original.host
  let refused = initial_issue_storage_transaction(
      key,
      request,
      scope,
      () => 10000L,
      after=() => Err(AuthorizationDenied),
    )
    is Err(InitialStorageJournal(AuthorizationDenied))
  let no_grant = host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound)
  let no_clock = host.database.read("credential-clock-v1", "host-lower-bound")
    is Err(@sqlite.NotFound)
  let issued = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap()
  let capacity = host.database
    .capacity_usage("client_local_grant_originals")
    .unwrap()
  host.close().unwrap()
  assert_true(refused && no_grant && no_clock)
  assert_eq(issued.revision, 0L)
  assert_eq(capacity.reserved_bytes, 0L)
}

///|
test "initial issue existing operation with missing use refuses without resampling or replacing" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-missing-use",
  )
  let host = key.original.host
  let first = initial_issue_storage_transaction(key, request, scope, () => {
    10000L
  }).unwrap()
  let original = initial_issue_storage_original(first)
  let bucket = "native-credential-use:" +
    local_original_grant_cid(original.grant)
  let use_row = host.database.read(bucket, scope.attempt_id).unwrap()
  host.journal
  .transaction(() => {
    host.database
    .remove_exact(bucket, scope.attempt_id, use_row.revision, use_row.body)
    .map_err(issue => Physical(issue))
  })
  .unwrap()
  let samples = Ref(0)
  let refused = initial_issue_storage_transaction(key, request, scope, () => {
      samples.val += 1
      999999L
    })
    is Err(
      InitialStorageCredential(@credential_resource.Journal(@sqlite.NotFound))
    )
  let count = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap().revision
  let still_missing = host.database.read(bucket, scope.attempt_id)
    is Err(@sqlite.NotFound)
  host.close().unwrap()
  assert_true(refused && still_missing)
  assert_eq(samples.val, 0)
  assert_eq(count, 1L)
}

///|
test "initial issue authenticated metadata rejects changed sample and copied operation packet" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-tamper",
  )
  let host = key.original.host
  let original = initial_issue_storage_original(
    initial_issue_storage_transaction(key, request, scope, () => 10000L).unwrap(),
  )
  let packet = original.initial_issue.unwrap()
  let payload = read_local_installation_authenticated_payload(host, packet).unwrap()
  let changed = @utf8.encode(
    @utf8.decode(payload).replace(old="10000", new="10001"),
  )
  let envelope = local_adoption_fields(packet, ["payload", "tag"]).unwrap()
  let tampered = local_adoption_record([
    ("payload", @base64.encode(changed)),
    ("tag", envelope[1]),
  ]).unwrap()
  let bad_sample = host.journal.transaction(() => {
      host.check_initial_signing_grant_original_locked(
        { ..original, initial_issue: Some(tampered), },
        scope.run_definition_cid,
      )
    })
    is Err(CustodyLost)
  guard original.grant is SigningGrant(grant) else { fail("expected Signing") }
  let copied = local_owned_grant_original(
    host.epoch.crypto,
    "different-operation",
    request,
    original.issuer_selection_cid,
    SigningGrant(grant),
  ).unwrap()
  let bad_operation = host.journal.transaction(() => {
      host.check_initial_signing_grant_original_locked(
        { ..copied, initial_issue: Some(packet), },
        scope.run_definition_cid,
      )
    })
    is Err(CustodyLost)
  host.close().unwrap()
  assert_true(bad_sample && bad_operation)
}

///|
test "initial issue refuses expired overflow foreign purpose and foreign scope before writes" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-invalid",
  )
  let host = key.original.host
  let expired = initial_issue_storage_transaction(
      key,
      request,
      scope,
      () => 10000L,
      bound=Some(10000L),
    )
    is Err(_)
  let overflow = initial_issue_storage_transaction(key, request, scope, () => {
      9223372036854775807L
    })
    is Err(_)
  let purpose = initial_issue_storage_transaction(
      key,
      request,
      { ..scope, purpose: @credential.HostAttestation, },
      () => 10000L,
    )
    is Err(_)
  let foreign = initial_issue_storage_transaction(
      key,
      request,
      { ..scope, key_generation_cid: "sha256:" + "f".repeat(64), },
      () => 10000L,
    )
    is Err(_)
  let unchanged = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap().revision ==
    0L
  host.close().unwrap()
  assert_true(expired && overflow && purpose && foreign && unchanged)
}

///|
test "initial issue another operation or changed attempt cannot replace original Unknown" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-unknown",
  )
  let host = key.original.host
  let original = initial_issue_storage_original(
    initial_issue_storage_transaction(key, request, scope, () => 10000L).unwrap(),
  )
  host.database
  .insert(
    "native-credential-outcome:" + local_original_grant_cid(original.grant),
    scope.attempt_id,
    b"unknown\n",
  )
  .unwrap()
  |> ignore
  let changed = initial_issue_storage_transaction(
      key,
      request,
      { ..scope, attempt_id: "replacement-attempt", },
      () => 20000L,
    )
    is Err(InitialStorageJournal(ChangedIntent))
  let different = initial_issue_storage_transaction(
      key,
      request,
      { ..scope, attempt_id: "replacement-attempt", },
      () => 20000L,
      operation="replacement-operation",
    )
    is Err(InitialStorageJournal(Checkpoint(NeedsOriginalContinuation)))
  let samples = Ref(0)
  let history = initial_issue_storage_transaction(key, request, scope, () => {
      samples.val += 1
      900000L
    }).unwrap()
    is InitialStorageHistory(_, _)
  let count = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap().revision
  host.close().unwrap()
  assert_true(changed && different && history)
  assert_eq(samples.val, 0)
  assert_eq(count, 1L)
}

///|
test "initial issue closure refuses autocommit and preserves old configured packet bytes" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-no-tx",
  )
  let samples = Ref(0)
  let refused = local_initial_signing_issue_storage_locked(
      key,
      request,
      scope,
      "operation",
      None,
      () => {
        samples.val += 1
        10000L
      },
      () => Ok(()),
    )
    is Err(InitialStorageJournal(Fenced))
  key.original.host.close().unwrap()
  let (host, _, old) = signing_grant_original_fixture(
    "initial-issue-old-packet",
  )
  let packet = local_grant_original_packet(old).unwrap()
  let object = local_grant_packet_object(packet).unwrap()
  let no_default = @decode.lookup(object, "initial_issue") is None
  let roundtrip = signing_grant_original_roundtrip(old).unwrap()
  let exact = local_grant_original_packet(roundtrip).unwrap() == packet
  host.close().unwrap()
  assert_true(refused && no_default && exact)
  assert_eq(samples.val, 0)
}

///|
test "initial issue lost COMMIT ACK fences original grant and claim without another clock or issue" {
  let (key, request, scope) = initial_issue_storage_fixture(
    "initial-issue-lost-ack",
  )
  let host = key.original.host
  let samples = Ref(0)
  client_test_fail_commit_reply(host.database, 1)
  let unknown = initial_issue_storage_transaction(key, request, scope, () => {
      samples.val += 1
      10000L
    })
    is Err(InitialStorageJournal(TransactionUnknown))
  let fenced = host.journal.fenced
  let again = initial_issue_storage_transaction(key, request, scope, () => {
      samples.val += 1
      20000L
    })
    is Err(InitialStorageJournal(Fenced))
  host.close().unwrap()
  assert_true(unknown && fenced && again)
  assert_eq(samples.val, 1)
}

///|
test "initial issue changed preimage and operation cannot bypass original claimed or Unknown custody" {
  for unknown in [false, true] {
    let (key, request, scope) = initial_issue_storage_fixture(
      if unknown {
        "initial-issue-changed-preimage-unknown"
      } else {
        "initial-issue-changed-preimage-claimed"
      },
    )
    let host = key.original.host
    let original = initial_issue_storage_original(
      initial_issue_storage_transaction(key, request, scope, () => 10000L).unwrap(),
    )
    let cid = local_original_grant_cid(original.grant)
    if unknown {
      host.database
      .insert(
        "native-credential-outcome:" + cid,
        scope.attempt_id,
        b"unknown\n",
      )
      .unwrap()
      |> ignore
    }
    let original_clock = host.database
      .read("credential-clock-v1", "host-lower-bound")
      .unwrap()
    let replacement_scope = {
      ..scope,
      attempt_id: "another-attempt-and-decision",
      preimage: "sha256:" + "9".repeat(64),
    }
    let refused = initial_issue_storage_transaction(
        key,
        request,
        replacement_scope,
        () => 20000L,
        operation="another-operation-and-decision",
      )
      is Err(InitialStorageJournal(Checkpoint(NeedsOriginalContinuation)))
    let count = host.database
      .read("client_local_grant_custody", "issued")
      .unwrap()
    let clock = host.database
      .read("credential-clock-v1", "host-lower-bound")
      .unwrap()
    let original_use = host.database
      .read("native-credential-use:" + cid, scope.attempt_id)
      .unwrap()
    let no_replacement_use = host.database.read(
        "native-credential-use:" + cid,
        replacement_scope.attempt_id,
      )
      is Err(@sqlite.NotFound)
    let history_only = initial_issue_storage_transaction(key, request, scope, () => {
        900000L
      }).unwrap()
      is InitialStorageHistory(_, _)
    host.close().unwrap()
    assert_true(refused && no_replacement_use && history_only)
    assert_eq(count.revision, 1L)
    assert_eq(clock.body, original_clock.body)
    assert_eq(clock.revision, original_clock.revision)
    assert_eq(original_use.revision, 0L)
  }
}
