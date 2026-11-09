///|
fn[T, E] paired_approval_require(value : Result[T, E], step~ : Int) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("paired Approval step " + step.to_string())
  }
}

///|
// Actual existing adopted Host/key + paired original Source/Preview scope.
// This verifies the original Approved Resolution and physical retention cleanup.
// Its Run remains Resuming: no resume claim, business update or Result is tested.
fn paired_initial_approved_proof_probe(
  fixture : PairedInitialReviewerFixture,
  binding : @client.NativeLocalEffectReviewerBinding,
  key : @client.NativeLocalInitialReviewerSigningKey,
  installed : @client.NativeLocalInstalledEffectReviewer,
  request : @host.ClientRequestIdentity,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Unit raise {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  let now = @values.epoch_milliseconds_timestamp(
    @env.now().reinterpret_as_int64(),
  ).unwrap()
  let authority = @host.client_request_authority_scope_cid(request)
  let unsigned = Json::object({
    "version": Json::string("actql-approval-attestation/0.1"),
    "effect_preview_cid": Json::string(
      checkpoint.checkpoint.required_artifact_cid,
    ),
    "review_projection_cid": Json::string(
      checkpoint.checkpoint.review_projection_cid,
    ),
    "approver": Json::string("operator"),
    "approved_at": Json::string(now),
    "authority_scope_cid": Json::string(authority),
    "claims": Json::array([Json::string("effect_scope_approved")]),
  }).stringify()
  let materials = key.prepare_approval_proof_materials(
      binding, unsigned, limits,
    )
    |> paired_approval_require(step=1)
  assert_true(
    materials.prepare_initial_resolution_signing("wrong-artifact") is Err(_),
  )
  let operation = "paired-approval-original"
  let scope = materials.prepare_signing_scope(operation)
    |> paired_approval_require(step=2)
  assert_true(
    materials.require_original_signing_scope({
      ..scope,
      purpose: @credential.HostAttestation,
    })
    is Err(_),
  )
  assert_true(
    materials.require_original_signing_scope({
      ..scope,
      preimage: "sha256:" + "0".repeat(64),
    })
    is Err(_),
  )
  assert_true(
    materials.require_original_signing_scope({
      ..scope,
      request_cid: "sha256:" + "0".repeat(64),
    })
    is Err(_),
  )
  let signing = materials.prepare_initial_approval_signing(operation)
    |> paired_approval_require(step=3)
  assert_true(signing.sign_candidate_once() is Err(_))
  let (evidence, evidence_cid) = signing.sign_approval_evidence_once()
    |> paired_approval_require(step=4)
  assert_true(signing.sign_approval_evidence_once() is Err(_))
  assert_true(signing.original_candidate() is Err(_))
  signing.close_checked() |> paired_approval_require(step=5)
  let changed_at = if now != checkpoint.checkpoint.created_at {
    checkpoint.checkpoint.created_at
  } else {
    checkpoint.checkpoint.expires_at
  }
  let changed = unsigned.replace_all(old=now, new=changed_at)
  guard changed != unsigned else { fail("distinct authored preimage required") }
  let changed = key.prepare_approval_proof_materials(binding, changed, limits)
    |> paired_approval_require(step=6)
  let attempted_reuse = changed.prepare_initial_approval_signing(operation)
    |> paired_approval_require(step=7)
  assert_true(attempted_reuse.sign_approval_evidence_once() is Err(_))
  attempted_reuse.close_checked() |> paired_approval_require(step=8)
  let unsigned = Json::object({
    "version": Json::string("actql-checkpoint-resolution/0.1"),
    "actor": Json::string("operator"),
    "checkpoint_id": Json::string(checkpoint.checkpoint.checkpoint_id),
    "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
    "decided_at": Json::string(now),
    "decision": Json::string("approved"),
    "required_artifact_cid": Json::string(
      checkpoint.checkpoint.required_artifact_cid,
    ),
    "review_projection_cid": Json::string(
      checkpoint.checkpoint.review_projection_cid,
    ),
    "resolution_id": Json::string("paired-approved-resolution"),
    "run_id": Json::string(checkpoint.checkpoint.run_id().unwrap()),
    "run_definition_cid": Json::string(
      checkpoint.checkpoint.run_definition_cid().unwrap(),
    ),
    "approval_evidence_cid": Json::string(evidence_cid),
  }).stringify()
  let materials = key.prepare_reviewer_proof_materials(
      binding, unsigned, limits,
    )
    |> paired_approval_require(step=11)
  assert_true(
    materials.prepare_initial_approval_signing("wrong-artifact") is Err(_),
  )
  let signing = materials.prepare_initial_resolution_signing(
      "paired-approved-resolution",
    )
    |> paired_approval_require(step=12)
  let candidate = match signing.sign_candidate_once() {
    Ok(value) => value
    Err(OriginalSigningUnavailable) => fail("Resolution signing: unavailable")
    Err(OriginalSigningJournal(CustodyLost)) =>
      fail("Resolution signing: journal custody")
    Err(OriginalSigningJournal(CapacityExceeded)) =>
      fail("Resolution signing: journal capacity")
    Err(OriginalSigningJournal(ChangedIntent)) =>
      fail("Resolution signing: changed intent")
    Err(OriginalSigningJournal(AuthorizationDenied)) =>
      fail("Resolution signing: authorization")
    Err(OriginalSigningJournal(Fenced)) => fail("Resolution signing: fenced")
    Err(OriginalSigningJournal(Encoding)) =>
      fail("Resolution signing: encoding")
    Err(OriginalSigningJournal(Physical(_))) =>
      fail("Resolution signing: physical Journal")
    Err(OriginalSigningJournal(Checkpoint(_))) =>
      fail("Resolution signing: Checkpoint")
    Err(OriginalSigningJournal(_)) => fail("Resolution signing: other Journal")
    Err(OriginalSigningOriginal(_)) => fail("Resolution signing: original")
    Err(OriginalSigningProof(_)) => fail("Resolution signing: proof")
    Err(OriginalSigningCredential(_)) => fail("Resolution signing: credential")
    Err(OriginalSigningPhysical(_)) =>
      fail("Resolution signing: physical signer")
  }
  let changed_resolution = unsigned.replace_all(
    old="paired-approved-resolution",
    new="changed-resolution",
  )
  let changed_materials = key.prepare_reviewer_proof_materials(
      binding, changed_resolution, limits,
    )
    |> paired_approval_require(step=22)
  signing.close_checked() |> paired_approval_require(step=23)
  let attempted_second = changed_materials.prepare_initial_resolution_signing(
      "changed-resolution",
    )
    |> paired_approval_require(step=24)
  assert_true(attempted_second.sign_candidate_once() is Err(_))
  attempted_second.close_checked() |> paired_approval_require(step=25)
  // Restore the original stored signature; this never re-enters the signer.
  let signing = materials.prepare_initial_resolution_signing(
      "paired-approved-resolution",
    )
    |> paired_approval_require(step=26)
  assert_eq(
    signing.sign_candidate_once() |> paired_approval_require(step=27),
    candidate,
  )
  let authenticated = binding.authenticate_resolution(candidate, limits)
    |> paired_approval_require(step=14)
  let account = fixture.host.restore_initial_host_signing_account(installed)
    |> paired_approval_require(step=15)
  let prepared = authenticated.prepare_initial_host_attestation(
      account,
      materials,
      "paired-approved-host",
      approval_evidence_wire=Some(evidence),
    )
    |> paired_approval_require(step=16)
  let host_signing = prepared.prepare_signing()
    |> paired_approval_require(step=17)
  let verified = host_signing.sign_once() |> paired_approval_require(step=18)
  assert_true(verified.contains("\"approval_evidence\":"))
  assert_true(verified.contains("\"decision\":\"approved\""))
  assert_true(host_signing.sign_once() is Err(_))
  let applied = host_signing.admit_original_resolution()
    |> paired_approval_require(step=21)
  assert_eq(
    @client.native_client_run_checkpoint_state(applied).unwrap().status,
    @publication.Resuming,
  )
  fixture.host_applied = true
  host_signing.close_checked() |> paired_approval_require(step=19)
  signing.close_checked() |> paired_approval_require(step=20)
}

///|
test "initial original Approval Resolution and independent Host signatures preserve scoped use and refusal" {
  let fixture = paired_initial_reviewer_fixture(
    attest_host=true,
    probe_approval=true,
  )
  native_local_effect_capture_acceptance(true, initial_reviewer=Some(fixture))
  assert_true(fixture.restored && fixture.host_applied)
}
