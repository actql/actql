///|
// Real initialized key/SQLite/physical signature and the existing explicit
// storage fixture. Its Checkpoint/subject is test DATA, not a genuine paired
// Source capture, public Reviewer current gate, Host attestation or CLI approval.
fn initial_candidate_fixture(
  name : String,
  tight? : Bool = false,
) -> (
  NativeLocalInitialReviewerSigningKey,
  NativeLocalGrantOriginal,
  @credential.LocalSigningCredentialUse,
  @crypto.OriginalKeySigningAttempt,
  String,
  @checkpoint.PreparedResolutionProof,
  String,
) raise {
  let (key, request, base) = initial_issue_storage_fixture(name)
  let definition = key.original.host.journal.retained(request).unwrap().unwrap().definition
  let checkpoint = checkpoint_test_artifact(definition)
  let unsigned = @utf8.decode(
    local_adoption_record([
      ("version", "actql-checkpoint-resolution/0.1"),
      ("actor", key.installed.reviewer.reviewer_id),
      ("checkpoint_id", checkpoint.checkpoint.checkpoint_id),
      ("checkpoint_cid", checkpoint.checkpoint_cid),
      ("decided_at", "2026-10-10T00:00:00.000Z"),
      ("decision", "rejected"),
      ("required_artifact_cid", "sha256:" + "3".repeat(64)),
      ("review_projection_cid", "sha256:" + "4".repeat(64)),
      ("resolution_id", "original-durable-resolution"),
      ("run_id", "checkpoint-run"),
      (
        "run_definition_cid",
        @publication.publication_contract_identity(definition),
      ),
    ]).unwrap(),
  )
  let limits = if tight {
    {
      ..native_checkpoint_limits(),
      max_wire_bytes: @utf8.encode(unsigned).length(),
    }
  } else {
    native_checkpoint_limits()
  }
  let proof = @checkpoint.prepare_resolution_proof(checkpoint, unsigned, limits).unwrap()
  let scope = {
    ..base,
    checkpoint_id: checkpoint.checkpoint.checkpoint_id,
    checkpoint_cid: checkpoint.checkpoint_cid,
    preimage: proof.preimage(),
  }
  let physical = prepare_local_initial_resolution_physical(key, scope).unwrap()
  guard initial_issue_storage_transaction(key, request, scope, () => 10000L).unwrap()
    is InitialStorageClaim(original, use) else {
    fail("fresh claim required")
  }
  let transport = physical.sign_once().unwrap()
  assert_true(
    key.original.host.epoch.crypto
    .verify_ed25519(
      key.original.public_key_pem,
      @utf8.encode(proof.preimage()),
      transport,
    )
    .unwrap(),
  )
  let signature = local_initial_resolution_signature_standard(transport).unwrap()
  let wire = if tight {
    ""
  } else {
    @checkpoint.seal_prepared_resolution_proof(proof, scope.key_id, signature).unwrap()
  }
  (key, original, use, physical, signature, proof, wire)
}

///|
test "restored original body keeps Core subject self identity and distinct cancellation decisions" {
  let (key, original, _, physical, signature, proof, wire) = initial_candidate_fixture(
    "candidate-body-current",
  )
  guard original.grant is SigningGrant(grant) else { fail("Signing required") }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  assert_true(
    local_initial_resolution_candidate_proof(
      proof.checkpoint(),
      wire,
      scope,
      signature,
      false,
    )
    is Ok(_),
  )
  assert_true(
    local_initial_resolution_candidate_proof(
      proof.checkpoint(),
      wire,
      scope,
      signature,
      true,
    )
    is Ok(_),
  )
  assert_true(
    local_initial_resolution_candidate_proof(
      proof.checkpoint(),
      wire + "\n",
      scope,
      signature,
      false,
    )
    is Err(CustodyLost),
  )
  assert_true(
    local_initial_resolution_candidate_proof(
      proof.checkpoint(),
      wire,
      { ..scope, checkpoint_cid: "sha256:" + "f".repeat(64), },
      signature,
      false,
    )
    is Err(CustodyLost),
  )
  // Pure codec/decision control only: these proof bytes are not authenticated
  // as an approved signature. The real caller independently verifies them.
  let value = @canonical.from_source(
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
    }).unwrap(),
    4096,
    64,
    65536,
    data_keys=true,
  )
  let body = @canonical.object_without_field(
    @canonical.object_without_field(value, "proof").unwrap(),
    "resolution_cid",
  ).unwrap()
  let unsigned = @canonical.stringify_value(body, 65536, 4096, 64).replace_all(
    old="\"decision\":\"rejected\"",
    new="\"approval_evidence_cid\":\"sha256:" +
      "5".repeat(64) +
      "\",\"decision\":\"approved\"",
  )
  let approved = @checkpoint.prepare_resolution_proof(
    proof.checkpoint(),
    unsigned,
    native_checkpoint_limits(),
  ).unwrap()
  let approved_wire = @checkpoint.seal_prepared_resolution_proof(
    approved,
    scope.key_id,
    signature,
  ).unwrap()
  let approved_scope = { ..scope, preimage: approved.preimage(), }
  assert_true(
    local_initial_resolution_candidate_proof(
      proof.checkpoint(),
      approved_wire,
      approved_scope,
      signature,
      false,
    )
    is Ok(_),
  )
  assert_true(
    local_initial_resolution_candidate_proof(
      proof.checkpoint(),
      approved_wire,
      approved_scope,
      signature,
      true,
    )
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  physical.close_checked().unwrap()
  key.original.host.close().unwrap()
}

///|
test "complete original Resolution shares signature outcome TX and existing grant capacity" {
  let (key, original, use, physical, signature, proof, wire) = initial_candidate_fixture(
    "candidate-confirmed",
  )
  let host = key.original.host
  host.journal
  .transaction(() => {
    store_local_initial_resolution_signature_locked(
      host,
      original,
      use,
      signature,
      prepared=Some(proof),
    )
  })
  .unwrap()
  assert_eq(
    host.journal
    .transaction(() => {
      local_initial_resolution_result_locked(host, original, use)
    })
    .unwrap(),
    (signature, Some(wire)),
  )
  let raw = host.database
    .read("client_local_signing_candidate_originals", original.operation_cid)
    .unwrap()
  assert_eq(raw.body, @utf8.encode(wire))
  let packet = host.database
    .read("client_local_signing_result_originals", original.operation_cid)
    .unwrap()
  let (_, _, runs) = host.journal
    .transaction(() => host.local_grant_custody(host.epoch.crypto))
    .unwrap()
  let (entries, used) = runs
    .get(local_original_grant_reservation_scope(original))
    .unwrap()
  assert_eq(entries, 1)
  assert_eq(
    used,
    local_grant_original_packet(original).unwrap().length() +
    packet.body.length() +
    raw.body.length(),
  )
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  physical.close_checked().unwrap()
  host.close().unwrap()

  // Legacy signature-only metadata is still readable, never a full candidate.
  let (key, original, use, physical, signature) = initial_resolution_physical_fixture(
    "candidate-legacy",
  )
  let host = key.original.host
  host.journal
  .transaction(() => {
    store_local_initial_resolution_signature_locked(
      host, original, use, signature,
    )
  })
  .unwrap()
  assert_eq(
    host.journal
    .transaction(() => {
      local_initial_resolution_result_locked(host, original, use)
    })
    .unwrap(),
    (signature, None),
  )
  assert_true(
    host.database.read(
      "client_local_signing_candidate_originals",
      original.operation_cid,
    )
    is Err(@sqlite.NotFound),
  )
  physical.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "candidate exact bytes missing rows and tighter original limits cannot be repaired" {
  let (key, original, use, physical, signature, proof, _) = initial_candidate_fixture(
    "candidate-tamper",
  )
  let host = key.original.host
  host.journal
  .transaction(() => {
    store_local_initial_resolution_signature_locked(
      host,
      original,
      use,
      signature,
      prepared=Some(proof),
    )
  })
  .unwrap()
  let row = host.database
    .read("client_local_signing_candidate_originals", original.operation_cid)
    .unwrap()
  let changed = @utf8.encode(@utf8.decode(row.body) + "\n")
  for variant in 0..<3 {
    let refused = Ref(false)
    let rolled_back : Result[Unit, NativeClientRunJournalIssue] = host.journal.transaction(() => {
        if variant < 2 {
          host.database
          .remove_exact(
            "client_local_signing_candidate_originals",
            original.operation_cid,
            row.revision,
            row.body,
          )
          .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
          .unwrap()
          if variant == 0 {
            // Still JSON-equivalent; exact retained bytes and HMAC digest differ.
            host.database
            .insert(
              "client_local_signing_candidate_originals",
              original.operation_cid,
              changed,
            )
            .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
            .unwrap()
            |> ignore
          }
          refused.val = local_initial_resolution_result_locked(
              host, original, use,
            )
            is Err(CustodyLost)
        } else {
          host.database
          .insert("client_local_signing_candidate_originals", "orphan", b"{}")
          .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
          .unwrap()
          |> ignore
          refused.val = host.local_grant_custody(host.epoch.crypto)
            is Err(CustodyLost)
        }
        Err(CustodyLost)
      },
    )
    assert_true(refused.val && rolled_back is Err(CustodyLost))
  }
  assert_eq(
    host.database
    .read("client_local_signing_candidate_originals", original.operation_cid)
    .unwrap().body,
    row.body,
  )
  physical.close_checked().unwrap()
  host.close().unwrap()

  let (key, original, use, physical, signature, proof, _) = initial_candidate_fixture(
    "candidate-tight",
    tight=true,
  )
  let host = key.original.host
  assert_true(
    host.journal.transaction(() => {
      store_local_initial_resolution_signature_locked(
        host,
        original,
        use,
        signature,
        prepared=Some(proof),
      )
    })
    is Err(Encoding),
  )
  assert_true(
    host.database.read(
      "client_local_signing_result_originals",
      original.operation_cid,
    )
    is Err(@sqlite.NotFound),
  )
  guard original.grant is SigningGrant(grant) else { fail("Signing required") }
  assert_true(
    @credential_resource.prepare_native_local_original_signing_history_candidate(
      host.database,
      grant,
    )
    .unwrap()
    .observed_outcome()
    is @credential_resource.Claimed,
  )
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  physical.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "lost candidate COMMIT return preserves full original wire without another proof or signing" {
  let name = "candidate-commit-return"
  let (key, original, use, physical, signature, proof, wire) = initial_candidate_fixture(
    name,
  )
  let host = key.original.host
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    host.journal.transaction(() => {
      store_local_initial_resolution_signature_locked(
        host,
        original,
        use,
        signature,
        prepared=Some(proof),
      )
    })
    is Err(TransactionUnknown),
  )
  let crypto = host.epoch.crypto
  physical.close_checked().unwrap()
  host.close().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    name
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
  // No original proof object, decision clock or physical signer enters readback.
  assert_eq(
    reopened.journal
    .transaction(() => {
      local_initial_resolution_result_locked(reopened, original, use)
    })
    .unwrap(),
    (signature, Some(wire)),
  )
  let (_, _, runs) = reopened.journal
    .transaction(() => reopened.local_grant_custody(crypto))
    .unwrap()
  assert_eq(runs.length(), 1)
  assert_true(physical.sign_once() is Err(@crypto.Signing(_)))
  reopened.close().unwrap()
}
