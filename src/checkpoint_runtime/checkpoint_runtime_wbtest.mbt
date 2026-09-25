///|
fn limits() -> WireLimits {
  { max_wire_bytes: 262144, max_nodes: 4096, max_depth: 32, }
}

///|
fn cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn effect_request() -> CheckpointRequest {
  {
    checkpoint_id: "cp-1",
    continuation_state_cid: cid("2"),
    subject: RunUnit(
      run_id="run-1",
      unit_id="unit-7",
      run_definition_cid=cid("1"),
    ),
    phase: Commit,
    kind: EffectSet,
    required_artifact_cid: cid("3"),
    review_projection_cid: cid("4"),
    requirements: [EffectScopeApproved, PartialApplicationAccepted],
    reason_code: "effect_review_required",
    human_summary: "Apply two ticket updates",
    created_at: "2026-09-25T10:00:00.000Z",
    expires_at: "2026-09-26T10:00:00.000Z",
  }
}

///|
fn run_scope_request() -> CheckpointRequest {
  {
    ..effect_request(),
    checkpoint_id: "cp-prep",
    subject: PrepareAttempt(prepare_attempt_id="attempt-1"),
    phase: Preflight,
    kind: RunScope,
    requirements: [InvocationScopeApproved],
  }
}

///|
fn sealed_of(request : CheckpointRequest) -> SealedCheckpoint {
  match seal_checkpoint(request, limits()) {
    Ok(value) => value
    Err(_) => abort("seal failed")
  }
}

///|
/// Canonical wire of `fields` with its self CID in `field`.
fn with_self_cid(fields : Map[String, Json], field : String) -> String {
  let body = canonical_of(Json::object(fields), limits()).unwrap()
  let identity = cid_of(body, limits()).unwrap()
  wire_of(
    @json.object_with_string_field(body, field, identity).unwrap(),
    limits(),
  ).unwrap()
}

///|
fn canonical_cid(wire : String) -> String {
  cid_of(parse_wire(wire, limits()).unwrap(), limits()).unwrap()
}

///|
fn proof(key_id : String) -> Json {
  Json::object({
    "scheme": Json::string("ed25519-v1"),
    "key_id": Json::string(key_id),
    "signature": Json::string("c2lnbmF0dXJl"),
  })
}

///|
fn effect_evidence(
  checkpoint : SealedCheckpoint,
  claims : Array[String],
  approver : String,
) -> String {
  let attestation = canonical_of(
    Json::object({
      "version": Json::string("actql-approval-attestation/0.1"),
      "effect_preview_cid": Json::string(
        checkpoint.checkpoint.required_artifact_cid,
      ),
      "review_projection_cid": Json::string(
        checkpoint.checkpoint.review_projection_cid,
      ),
      "approver": Json::string(approver),
      "approved_at": Json::string("2026-09-25T11:00:00.000Z"),
      "authority_scope_cid": Json::string(cid("5")),
      "claims": string_array_json(claims),
      "proof": proof("reviewer-key"),
    }),
    limits(),
  ).unwrap()
  let attestation_cid = cid_of(attestation, limits()).unwrap()
  let complete = @json.object_with_string_field(
    attestation, "attestation_cid", attestation_cid,
  ).unwrap()
  let evidence = canonical_of(
    Json::object({
      "version": Json::string("actql-checkpoint-approval-evidence/0.1"),
      "kind": Json::string("effect_set"),
      "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
      "review_projection_cid": Json::string(
        checkpoint.checkpoint.review_projection_cid,
      ),
      "compatibility_approval": to_json(complete),
    }),
    limits(),
  ).unwrap()
  wire_of(evidence, limits()).unwrap()
}

///|
fn run_scope_evidence(checkpoint : SealedCheckpoint) -> String {
  let approval = canonical_of(
    Json::object({
      "version": Json::string("actql-run-scope-approval/0.1"),
      "prepared_invocation_cid": Json::string(
        checkpoint.checkpoint.required_artifact_cid,
      ),
      "review_projection_cid": Json::string(
        checkpoint.checkpoint.review_projection_cid,
      ),
      "claim": Json::string("invocation_scope_approved"),
      "approver": Json::string("alice"),
      "approved_at": Json::string("2026-09-25T11:00:00.000Z"),
      "expires_at": Json::string("2026-09-26T10:00:00.000Z"),
      "proof": proof("reviewer-key"),
    }),
    limits(),
  ).unwrap()
  let approval_cid = cid_of(approval, limits()).unwrap()
  let complete = @json.object_with_string_field(
    approval, "run_scope_approval_cid", approval_cid,
  ).unwrap()
  wire_of(
    canonical_of(
      Json::object({
        "version": Json::string("actql-checkpoint-approval-evidence/0.1"),
        "kind": Json::string("run_scope"),
        "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
        "review_projection_cid": Json::string(
          checkpoint.checkpoint.review_projection_cid,
        ),
        "compatibility_approval": to_json(complete),
      }),
      limits(),
    ).unwrap(),
    limits(),
  ).unwrap()
}

///|
fn resolution_fields_for(
  checkpoint : SealedCheckpoint,
  decision : String,
  evidence_cid : String?,
) -> Map[String, Json] {
  let fields : Map[String, Json] = {
    "version": Json::string("actql-checkpoint-resolution/0.1"),
    "resolution_id": Json::string("res-" + decision),
    "checkpoint_id": Json::string(checkpoint.checkpoint.checkpoint_id),
    "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
    "decision": Json::string(decision),
    "actor": Json::string("alice"),
    "decided_at": Json::string("2026-09-25T12:00:00.000Z"),
    "required_artifact_cid": Json::string(
      checkpoint.checkpoint.required_artifact_cid,
    ),
    "review_projection_cid": Json::string(
      checkpoint.checkpoint.review_projection_cid,
    ),
    "proof": proof("reviewer-key"),
  }
  if evidence_cid is Some(value) {
    fields["approval_evidence_cid"] = Json::string(value)
  }
  match checkpoint.checkpoint.subject {
    RunUnit(run_id~, run_definition_cid~, ..) => {
      fields["run_id"] = Json::string(run_id)
      fields["run_definition_cid"] = Json::string(run_definition_cid)
    }
    PrepareAttempt(prepare_attempt_id~) =>
      fields["prepare_attempt_id"] = Json::string(prepare_attempt_id)
  }
  fields
}

///|
/// What a Host authorization port reports after verifying `proof.signature`
/// over the unsigned Resolution CID text.
fn authentication(resolution : String) -> HostAuthentication {
  {
    key_id: "reviewer-key",
    reviewer_id: "alice",
    authority_context_cid: cid("6"),
    policy_cid: cid("7"),
    proof_preimage: resolution_proof_preimage(resolution, limits()).unwrap(),
  }
}

///|
fn authorities() -> Array[ReviewerAuthority] {
  [{ key_id: "reviewer-key", reviewer_id: "alice", }]
}

///|
fn admit(
  checkpoint : SealedCheckpoint,
  resolution : String,
  evidence : String?,
) -> Result[AdmittedResolution, ResolutionIssue] {
  admit_checkpoint_resolution(
    checkpoint,
    resolution,
    evidence,
    authentication(resolution),
    authorities(),
    "2026-09-25T12:00:01.000Z",
    limits(),
  )
}

///|
fn approved_effect() -> (SealedCheckpoint, String, String) {
  let checkpoint = sealed_of(effect_request())
  let evidence = effect_evidence(
    checkpoint,
    ["effect_scope_approved", "partial_application_accepted"],
    "alice",
  )
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  (checkpoint, resolution, evidence)
}

///|
fn[T] issue_of(result : Result[T, ResolutionIssue]) -> ResolutionIssue? {
  match result {
    Ok(_) => None
    Err(issue) => Some(issue)
  }
}

///|
test "checkpoint seal is canonical, self-identified and re-admitted" {
  let checkpoint = sealed_of(effect_request())
  assert_true(valid_cid(checkpoint.checkpoint_cid))
  assert_true(checkpoint.wire.has_prefix("{\"checkpoint_cid\":"))
  assert_true(
    checkpoint.wire.contains(
      "\"subject\":{\"continuation\":\"resume_unit\",\"kind\":\"run_unit\",\"run_id\":\"run-1\",\"unit_id\":\"unit-7\"}",
    ),
  )
  assert_true(
    checkpoint.wire.contains(
      "\"required_artifact\":{\"artifact_cid\":\"" +
      cid("3") +
      "\",\"artifact_type\":\"effect_set_preview\"}",
    ),
  )
  let body = @json.object_without_field(
    parse_wire(checkpoint.wire, limits()).unwrap(),
    "checkpoint_cid",
  ).unwrap()
  assert_eq(cid_of(body, limits()), Some(checkpoint.checkpoint_cid))
  assert_eq(admit_checkpoint_wire(checkpoint.wire, limits()), Ok(checkpoint))
  let tampered = checkpoint.wire.replace(old="unit-7", new="unit-8")
  assert_eq(admit_checkpoint_wire(tampered, limits()), Err(IdentityMismatch))
  let extra = checkpoint.wire.replace(
    old="{\"checkpoint_cid\"",
    new="{\"x\":1,\"checkpoint_cid\"",
  )
  assert_eq(admit_checkpoint_wire(extra, limits()), Err(UnknownField("x")))
  let prep = sealed_of(run_scope_request())
  assert_true(
    prep.wire.contains(
      "\"subject\":{\"continuation\":\"start_run\",\"kind\":\"prepare_attempt\",\"prepare_attempt_id\":\"attempt-1\"}",
    ),
  )
  assert_eq(admit_checkpoint_wire(prep.wire, limits()), Ok(prep))
}

///|
test "checkpoint combinations are the closed protocol table" {
  let base = effect_request()
  let prep = PrepareAttempt(prepare_attempt_id="attempt-1")
  let unit = RunUnit(run_id="run-1", unit_id="u", run_definition_cid=cid("1"))
  let cases : Array[(CheckpointSubject, CheckpointPhase, CheckpointKind, Bool)] = [
    (prep, Preflight, RunScope, true),
    (prep, Preflight, ReadAccess, true),
    (unit, Preflight, ReadAccess, true),
    (unit, Preflight, DataEgress, true),
    (unit, Preflight, CostScope, true),
    (unit, Commit, EffectSet, true),
    (unit, Preflight, RunScope, false),
    (prep, Preflight, DataEgress, false),
    (prep, Preflight, CostScope, false),
    (prep, Commit, EffectSet, false),
    (unit, Preflight, EffectSet, false),
    (unit, Commit, ReadAccess, false),
  ]
  for case in cases {
    let (subject, phase, kind, valid) = case
    assert_eq(checkpoint_combination_valid(subject, phase, kind), valid)
    let requirements = if kind == EffectSet {
      [EffectScopeApproved]
    } else {
      [InvocationScopeApproved]
    }
    let result = seal_checkpoint(
      { ..base, subject, phase, kind, requirements, },
      limits(),
    )
    if valid {
      assert_true(result is Ok(_))
    } else {
      assert_eq(result.map(_ => ()), Err(UnsupportedCombination))
    }
  }
}

///|
test "requirements are per-kind data from the closed lists" {
  let base = effect_request()
  assert_true(
    seal_checkpoint({ ..base, requirements: [EffectScopeApproved], }, limits())
    is Ok(_),
  )
  for
    requirements in [
      [InvocationScopeApproved],
      [PartialApplicationAccepted],
      [PartialApplicationAccepted, EffectScopeApproved],
      [],
    ] {
    assert_eq(
      seal_checkpoint({ ..base, requirements, }, limits()).map(_ => ()),
      Err(InvalidRequirements),
    )
  }
  let prep = run_scope_request()
  assert_eq(
    seal_checkpoint({ ..prep, requirements: [EffectScopeApproved], }, limits()).map(_ => {
        ()
      },
    ),
    Err(InvalidRequirements),
  )
}

///|
test "checkpoint fields, identities and time window are validated" {
  let base = effect_request()
  let invalid : Array[(CheckpointRequest, CheckpointIssue)] = [
    ({ ..base, expires_at: base.created_at, }, InvalidTimeWindow),
    ({ ..base, expires_at: "2026-09-24T10:00:00.000Z", }, InvalidTimeWindow),
    (
      { ..base, created_at: "2026-13-25T10:00:00.000Z", },
      InvalidField("created_at"),
    ),
    (
      { ..base, created_at: "2026-02-30T10:00:00.000Z", },
      InvalidField("created_at"),
    ),
    (
      {
        ..base,
        subject: RunUnit(
          run_id="run-1",
          unit_id="unit-7",
          run_definition_cid="sha256:AB",
        ),
      },
      InvalidField("run_definition_cid"),
    ),
    (
      {
        ..base,
        subject: RunUnit(
          run_id="",
          unit_id="unit-7",
          run_definition_cid=cid("1"),
        ),
      },
      InvalidField("subject.run_id"),
    ),
    ({ ..base, human_summary: "Cafe\u{0301}", }, InvalidField("human_summary")),
    ({ ..base, checkpoint_id: "", }, InvalidField("checkpoint_id")),
  ]
  for case in invalid {
    let (request, issue) = case
    assert_eq(seal_checkpoint(request, limits()).map(_ => ()), Err(issue))
  }
}

///|
test "waiting is projected only from a persisted checkpoint" {
  let checkpoint = sealed_of(effect_request())
  assert_eq(
    confirm_checkpoint_persisted(checkpoint, checkpoint.wire + " ").map(_ => ()),
    Err(PersistedWireMismatch),
  )
  let persisted = confirm_checkpoint_persisted(checkpoint, checkpoint.wire).unwrap()
  let wire = issue_waiting_run_state(
    persisted,
    "2026-09-25T10:00:00.000Z",
    ["tickets", "audit"],
    limits(),
  ).unwrap()
  assert_eq(
    wire,
    "{\"checkpoint\":{\"checkpoint_cid\":\"" +
    checkpoint.checkpoint_cid +
    "\",\"checkpoint_id\":\"cp-1\",\"kind\":\"effect_set\"},\"next_action\":{\"checkpoint_id\":\"cp-1\",\"kind\":\"resolve_checkpoint\"},\"result_availability\":{\"audit\":{\"observed_at\":\"2026-09-25T10:00:00.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"},\"tickets\":{\"observed_at\":\"2026-09-25T10:00:00.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"}},\"result_available\":false,\"run_id\":\"run-1\",\"status\":\"waiting_checkpoint\",\"updated_at\":\"2026-09-25T10:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
  )
  let view = admit_run_state_wire(wire, limits()).unwrap()
  assert_eq(view.status, WaitingCheckpoint)
  assert_eq(view.checkpoint_cid, Some(checkpoint.checkpoint_cid))
  assert_eq(
    issue_lifecycle_run_state(
      "run-1",
      WaitingCheckpoint,
      "2026-09-25T10:00:00.000Z",
      ["tickets"],
      limits(),
    ),
    Err(RunStateInvalidField("status")),
  )
  assert_eq(
    issue_waiting_run_state(persisted, "2026-09-25T10:00:00.000Z", [], limits()),
    Err(RunStateRelation(EmptyDeclaredResults)),
  )
}

///|
test "lifecycle run states and admitted continuation outcomes" {
  let cancelled = issue_lifecycle_run_state(
    "run-1",
    Cancelled,
    "2026-09-25T13:00:00.000Z",
    ["tickets"],
    limits(),
  ).unwrap()
  assert_true(cancelled.contains("\"next_action\":{\"kind\":\"none\"}"))
  assert_eq(
    admit_run_state_wire(cancelled, limits()).unwrap().status,
    Cancelled,
  )
  assert_true(
    issue_lifecycle_run_state(
      "run-1",
      Succeeded,
      "2026-09-25T13:00:00.000Z",
      ["tickets"],
      limits(),
    )
    is Err(_),
  )
  let succeeded = @publication.issue_succeeded_run_state(
    "run-1",
    "2026-09-25T13:00:00.000Z",
    ["tickets"],
    [{ name: "tickets", state: Available, reason: ConfirmedPresent, }],
    ["2026-09-25T13:00:00.000Z"],
    65536,
    4096,
    32,
  ).unwrap()
  let view = admit_run_state_wire(succeeded, limits()).unwrap()
  assert_eq(view.status, Succeeded)
  assert_eq(view.checkpoint_cid, None)
  let waiting_without_checkpoint = cancelled.replace(
    old="\"cancelled\"",
    new="\"waiting_checkpoint\"",
  )
  assert_true(
    admit_run_state_wire(waiting_without_checkpoint, limits()) is Err(_),
  )
  let foreign = cancelled.replace(old="\"none\"", new="\"read_result\"")
  assert_true(admit_run_state_wire(foreign, limits()) is Err(_))
}

///|
test "approved effect resolution produces the verified wrapper and intent" {
  let (checkpoint, resolution, evidence) = approved_effect()
  let admitted = admit(checkpoint, resolution, Some(evidence)).unwrap()
  assert_eq(admitted.decision, Approved)
  assert_eq(
    Some(admitted.resolution_cid),
    string_field(parse_wire(resolution, limits()).unwrap(), "resolution_cid"),
  )
  // The Host signs the unsigned wrapper CID text, not the canonical bytes.
  assert_true(valid_cid(admitted.attestation_preimage))
  let verified = seal_verified_resolution(
    admitted,
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  let value = parse_wire(verified.wire, limits()).unwrap()
  let body = @json.object_without_field(value, "verified_resolution_cid").unwrap()
  assert_eq(cid_of(body, limits()), Some(verified.verified_resolution_cid))
  let without_attestation = @json.object_without_field(body, "host_attestation").unwrap()
  assert_eq(
    cid_of(without_attestation, limits()),
    Some(admitted.attestation_preimage),
  )
  assert_true(verified.wire.contains("\"approval_evidence\":"))
  assert_eq(
    verified_resolution_attestation_preimage(verified.wire, limits()),
    Ok(admitted.attestation_preimage),
  )
  assert_eq(
    verified.resume_intent_id,
    resume_intent_id(
      checkpoint.checkpoint_cid,
      verified.resolution_cid,
      limits(),
    ),
  )
  assert_true(verified.wire.contains("\"verified_reviewer_id\":\"alice\""))
  assert_true(
    verified.wire.contains(
      "\"requirements\":[\"effect_scope_approved\",\"partial_application_accepted\"]",
    ),
  )
  assert_eq(verified.verified_at, "2026-09-25T12:00:01.000Z")
  let authorization = @json.object_field(value, "authorization_evidence").unwrap()
  assert_eq(
    cid_of(authorization, limits()),
    string_field(value, "authorization_evidence_cid"),
  )
  assert_eq(
    string_field(authorization, "authority_context_cid"),
    string_field(value, "authorization_context_cid"),
  )
  assert_eq(
    string_field(authorization, "resolution_cid"),
    Some(verified.resolution_cid),
  )
  assert_eq(
    seal_verified_resolution(admitted, "", "aG9zdA==", limits()).map(_ => ()),
    Err(InvalidAttestation),
  )
  assert_eq(
    seal_verified_resolution(admitted, "host-key", "not base64!", limits()).map(_ => {
        ()
      },
    ),
    Err(InvalidAttestation),
  )
}

///|
test "effect requirements are satisfied by carried claims" {
  let checkpoint = sealed_of({
    ..effect_request(),
    requirements: [EffectScopeApproved],
  })
  let evidence = effect_evidence(checkpoint, ["effect_scope_approved"], "alice")
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  assert_true(admit(checkpoint, resolution, Some(evidence)) is Ok(_))
  let strict = sealed_of(effect_request())
  let weak = effect_evidence(strict, ["effect_scope_approved"], "alice")
  let weak_resolution = with_self_cid(
    resolution_fields_for(strict, "approved", Some(canonical_cid(weak))),
    "resolution_cid",
  )
  assert_eq(
    issue_of(admit(strict, weak_resolution, Some(weak))),
    Some(EvidenceMismatch("claims")),
  )
}

///|
test "run scope approval evidence binds the prepared invocation" {
  let checkpoint = sealed_of(run_scope_request())
  let evidence = run_scope_evidence(checkpoint)
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  let verified = seal_verified_resolution(
    admit(checkpoint, resolution, Some(evidence)).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  assert_eq(verified.decision, Approved)
  assert_true(
    verified.wire.contains("\"requirements\":[\"invocation_scope_approved\"]"),
  )
  let other = sealed_of({
    ..run_scope_request(),
    required_artifact_cid: cid("9"),
  })
  let foreign = with_self_cid(
    resolution_fields_for(other, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  assert_true(issue_of(admit(other, foreign, Some(evidence))) is Some(_))
}

///|
test "rejection carries no evidence and creates no resume intent" {
  let checkpoint = sealed_of(effect_request())
  let rejection = with_self_cid(
    resolution_fields_for(checkpoint, "rejected", None),
    "resolution_cid",
  )
  let verified = seal_verified_resolution(
    admit(checkpoint, rejection, None).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  assert_eq(verified.decision, Rejected)
  assert_eq(verified.resume_intent_id, None)
  assert_true(!verified.wire.contains("approval_evidence"))
  let (_, _, evidence) = approved_effect()
  assert_eq(
    issue_of(admit(checkpoint, rejection, Some(evidence))),
    Some(EvidenceForbidden),
  )
  let rejected_with_cid = with_self_cid(
    resolution_fields_for(checkpoint, "rejected", Some(cid("8"))),
    "resolution_cid",
  )
  assert_eq(
    issue_of(admit(checkpoint, rejected_with_cid, None)),
    Some(EvidenceForbidden),
  )
  let approved_without_cid = with_self_cid(
    resolution_fields_for(checkpoint, "approved", None),
    "resolution_cid",
  )
  assert_eq(
    issue_of(admit(checkpoint, approved_without_cid, None)),
    Some(EvidenceRequired),
  )
  let (effect, resolution, _) = approved_effect()
  assert_eq(issue_of(admit(effect, resolution, None)), Some(EvidenceRequired))
}

///|
test "decision time must lie in the checkpoint window and not after verification" {
  let checkpoint = sealed_of(effect_request())
  let cases = [
    ("2026-09-25T09:59:59.999Z", DecisionOutsideWindow),
    ("2026-09-26T10:00:00.000Z", DecisionOutsideWindow),
    ("2026-09-25T12:00:02.000Z", DecisionAfterVerification),
  ]
  for case in cases {
    let (decided_at, issue) = case
    let fields = resolution_fields_for(checkpoint, "rejected", None)
    fields["decided_at"] = Json::string(decided_at)
    let resolution = with_self_cid(fields, "resolution_cid")
    assert_eq(issue_of(admit(checkpoint, resolution, None)), Some(issue))
  }
  let fields = resolution_fields_for(checkpoint, "rejected", None)
  fields["decided_at"] = Json::string(checkpoint.checkpoint.created_at)
  assert_true(
    admit(checkpoint, with_self_cid(fields, "resolution_cid"), None) is Ok(_),
  )
}

///|
test "resolution binds the exact checkpoint and its own identity" {
  let checkpoint = sealed_of(effect_request())
  for
    field in [
      "checkpoint_id", "checkpoint_cid", "run_id", "run_definition_cid", "required_artifact_cid",
      "review_projection_cid",
    ] {
    let fields = resolution_fields_for(checkpoint, "rejected", None)
    fields[field] = Json::string(
      if field.has_suffix("_cid") {
        cid("e")
      } else {
        "other"
      },
    )
    assert_eq(
      issue_of(admit(checkpoint, with_self_cid(fields, "resolution_cid"), None)),
      Some(CheckpointBindingMismatch(field)),
    )
  }
  let good = with_self_cid(
    resolution_fields_for(checkpoint, "rejected", None),
    "resolution_cid",
  )
  let tampered = good.replace(
    old="\"actor\":\"alice\"",
    new="\"actor\":\"alicf\"",
  )
  assert_eq(
    issue_of(admit(checkpoint, tampered, None)),
    Some(ResolutionIdentityMismatch),
  )
  let extra = good.replace(old="{\"actor\"", new="{\"x\":1,\"actor\"")
  assert_eq(
    issue_of(admit(checkpoint, extra, None)),
    Some(ResolutionUnknownField("x")),
  )
}

///|
test "host authentication must agree with the resolution and authority set" {
  let checkpoint = sealed_of(effect_request())
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "rejected", None),
    "resolution_cid",
  )
  let authentication = fn() { authentication(resolution) }
  let check = fn(
    auth : HostAuthentication,
    allowed : Array[ReviewerAuthority],
  ) {
    issue_of(
      admit_checkpoint_resolution(
        checkpoint,
        resolution,
        None,
        auth,
        allowed,
        "2026-09-25T12:00:01.000Z",
        limits(),
      ),
    )
  }
  assert_eq(
    check({ ..authentication(), key_id: "other-key", }, authorities()),
    Some(AuthenticationMismatch("key_id")),
  )
  assert_eq(
    check({ ..authentication(), reviewer_id: "mallory", }, authorities()),
    Some(AuthenticationMismatch("reviewer_id")),
  )
  assert_eq(
    check({ ..authentication(), policy_cid: "policy", }, authorities()),
    Some(AuthenticationMismatch("policy_cid")),
  )
  assert_eq(check(authentication(), []), Some(AuthorityNotPermitted))
  assert_eq(
    check(authentication(), [{ key_id: "reviewer-key", reviewer_id: "bob", }]),
    Some(AuthorityNotPermitted),
  )
  assert_eq(check(authentication(), authorities()), None)
  // The port must have verified the signature over the unsigned Resolution
  // CID text, not over the self CID or the canonical body.
  let self_cid_text = string_field(
    parse_wire(resolution, limits()).unwrap(),
    "resolution_cid",
  ).unwrap()
  assert_eq(
    check({ ..authentication(), proof_preimage: self_cid_text, }, authorities()),
    Some(AuthenticationMismatch("proof_preimage")),
  )
}

///|
test "approval evidence bytes must hash to the authored evidence cid" {
  let (checkpoint, resolution, evidence) = approved_effect()
  let altered = evidence.replace(
    old="2026-09-25T11:00:00.000Z",
    new="2026-09-25T11:00:00.001Z",
  )
  assert_eq(
    issue_of(admit(checkpoint, resolution, Some(altered))),
    Some(EvidenceMismatch("approval_evidence_cid")),
  )
  let impostor = effect_evidence(
    checkpoint,
    ["effect_scope_approved", "partial_application_accepted"],
    "mallory",
  )
  let impostor_resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(impostor))),
    "resolution_cid",
  )
  assert_eq(
    issue_of(admit(checkpoint, impostor_resolution, Some(impostor))),
    Some(EvidenceMismatch("approver")),
  )
}

///|
test "resolution commit is idempotent, conflicting, or expired" {
  let (checkpoint, resolution, evidence) = approved_effect()
  let verified = seal_verified_resolution(
    admit(checkpoint, resolution, Some(evidence)).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  assert_eq(
    decide_resolution_commit(checkpoint, Open, verified),
    CommitResolution,
  )
  assert_eq(
    decide_resolution_commit(
      checkpoint,
      Resolved(verified.resolution_cid),
      verified,
    ),
    DuplicateResolution,
  )
  assert_eq(
    decide_resolution_commit(checkpoint, Resolved(cid("f")), verified),
    ConflictingResolution,
  )
  assert_eq(
    decide_resolution_commit(checkpoint, Expired, verified),
    CheckpointExpired,
  )
  let late = seal_verified_resolution(
    admit_checkpoint_resolution(
      checkpoint,
      resolution,
      Some(evidence),
      authentication(resolution),
      authorities(),
      "2026-09-26T10:00:00.000Z",
      limits(),
    ).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  assert_eq(decide_resolution_commit(checkpoint, Open, late), CheckpointExpired)
  assert_eq(
    decide_resolution_commit(checkpoint, Resolved(late.resolution_cid), late),
    DuplicateResolution,
  )
  let other = sealed_of({ ..effect_request(), checkpoint_id: "cp-2", })
  assert_eq(
    decide_resolution_commit(other, Open, verified),
    ConflictingResolution,
  )
  assert_eq(resolution_run_status(Approved), Resuming)
  assert_eq(resolution_run_status(Rejected), Cancelled)
  assert_eq(
    checkpoint_expired_at(checkpoint, "2026-09-26T09:59:59.999Z"),
    Ok(false),
  )
  assert_eq(
    checkpoint_expired_at(checkpoint, "2026-09-26T10:00:00.000Z"),
    Ok(true),
  )
}

///|
test "run transitions follow the public table" {
  let allowed : Array[
    (@publication.RunOutcomeStatus, @publication.RunOutcomeStatus),
  ] = [
    (Preparing, WaitingCheckpoint),
    (Running, WaitingCheckpoint),
    (Resuming, WaitingCheckpoint),
    (WaitingCheckpoint, Resuming),
    (WaitingCheckpoint, Cancelled),
    (WaitingCheckpoint, NeedsReconciliation),
    (Resuming, Succeeded),
    (Resuming, Failed),
    (Resuming, NeedsReconciliation),
    (Resuming, Cancelled),
  ]
  for pair in allowed {
    let (from, to) = pair
    assert_true(run_transition_allowed(from, to))
  }
  let denied : Array[
    (@publication.RunOutcomeStatus, @publication.RunOutcomeStatus),
  ] = [
    (Resuming, Running),
    (WaitingCheckpoint, Running),
    (WaitingCheckpoint, WaitingCheckpoint),
    (WaitingCheckpoint, Succeeded),
    (WaitingCheckpoint, Failed),
    (Cancelled, Resuming),
    (Cancelled, NeedsReconciliation),
    (Succeeded, WaitingCheckpoint),
    (Failed, Resuming),
    (NeedsReconciliation, WaitingCheckpoint),
  ]
  for pair in denied {
    let (from, to) = pair
    assert_true(!run_transition_allowed(from, to))
  }
  assert_true(!resume_completion_allowed(Running))
  assert_true(!resume_completion_allowed(Resuming))
  assert_true(resume_completion_allowed(WaitingCheckpoint))
  assert_true(resume_completion_allowed(Succeeded))
}

///|
fn binding() -> ResumeBinding {
  { authorization_context_cid: cid("a"), environment_binding_cid: cid("b"), }
}

///|
test "resume claims are fenced by a monotonically increasing generation" {
  let pending : ResumeIntentView = {
    state: ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  }
  assert_eq(
    decide_resume_claim(pending, "worker-a", 1000L, 500L, binding(), binding()),
    Ok(ClaimIntent(1L, 1500L)),
  )
  let claimed : ResumeIntentView = {
    state: ResumeClaimed,
    generation: 1L,
    claimant: "worker-a",
    lease_expires_ms: 1500L,
  }
  assert_eq(
    decide_resume_claim(claimed, "worker-b", 1499L, 500L, binding(), binding()),
    Ok(ClaimBusy),
  )
  assert_eq(
    decide_resume_claim(claimed, "worker-b", 1500L, 500L, binding(), binding()),
    Ok(ClaimIntent(2L, 2000L)),
  )
  assert_eq(
    decide_resume_claim(
      { ..claimed, state: ResumeCompleted, },
      "worker-b",
      9000L,
      500L,
      binding(),
      binding(),
    ),
    Ok(ClaimCompleted),
  )
  let changed = { ..binding(), environment_binding_cid: cid("c"), }
  assert_eq(
    decide_resume_claim(pending, "worker-a", 1000L, 500L, binding(), changed),
    Ok(ClaimInvalidated(1L)),
  )
  assert_eq(
    decide_resume_claim(pending, "", 1000L, 500L, binding(), binding()),
    Err(InvalidClaimant),
  )
  assert_eq(
    decide_resume_claim(pending, "w", 1000L, 0L, binding(), binding()),
    Err(InvalidLease),
  )
  assert_eq(
    decide_resume_claim(pending, "w", -1L, 10L, binding(), binding()),
    Err(InvalidClock),
  )
  assert_eq(
    decide_resume_claim(
      pending,
      "w",
      1L,
      10L,
      { ..binding(), authorization_context_cid: "x", },
      binding(),
    ),
    Err(InvalidBinding),
  )
  let current : ResumeClaim = { claimant: "worker-a", generation: 1L, }
  assert_eq(decide_resume_fence(claimed, current, 1499L), FenceCurrent)
  assert_eq(decide_resume_fence(claimed, current, 1500L), FenceStale)
  assert_eq(
    decide_resume_fence({ ..claimed, generation: 2L, }, current, 1000L),
    FenceStale,
  )
  assert_eq(
    decide_resume_fence(claimed, { ..current, claimant: "worker-b", }, 1000L),
    FenceStale,
  )
  assert_eq(
    decide_resume_fence({ ..claimed, state: ResumeCompleted, }, current, 1000L),
    FenceStale,
  )
  assert_eq(
    resume_intent_id(cid("1"), cid("2"), limits()),
    resume_intent_id(cid("1"), cid("2"), limits()),
  )
  assert_true(
    resume_intent_id(cid("1"), cid("2"), limits()) !=
    resume_intent_id(cid("1"), cid("3"), limits()),
  )
}

///|
test "a checkpoint body wire seals to the same artifact" {
  let checkpoint = sealed_of(effect_request())
  let body = wire_of(
    @json.object_without_field(
      parse_wire(checkpoint.wire, limits()).unwrap(),
      "checkpoint_cid",
    ).unwrap(),
    limits(),
  ).unwrap()
  assert_eq(seal_checkpoint_body(body, limits()), Ok(checkpoint))
  assert_eq(
    seal_checkpoint_body(checkpoint.wire, limits()).map(_ => ()),
    Err(UnknownField("checkpoint_cid")),
  )
  let wrong_artifact = body.replace(
    old="effect_set_preview",
    new="prepared_invocation",
  )
  assert_eq(
    seal_checkpoint_body(wrong_artifact, limits()).map(_ => ()),
    Err(UnsupportedCombination),
  )
}

///|
test "only a run-unit checkpoint carries the run identity" {
  let prep = sealed_of(run_scope_request())
  assert_true(!prep.wire.contains("\"run_id\""))
  assert_true(!prep.wire.contains("\"run_definition_cid\""))
  assert_eq(prep.checkpoint.run_id(), None)
  assert_eq(prep.checkpoint.run_definition_cid(), None)
  assert_eq(prep.checkpoint.prepare_attempt_id(), Some("attempt-1"))
  let unit = sealed_of(effect_request())
  assert_true(unit.wire.contains("\"run_definition_cid\":\"" + cid("1") + "\""))
  assert_true(unit.wire.contains("\"run_id\":\"run-1\""))
  assert_eq(unit.checkpoint.run_id(), Some("run-1"))
  let body = fn(artifact : SealedCheckpoint) -> Map[String, Json] {
    let map : Map[String, Json] = Map([])
    for
      field in @json.object_fields(
        @json.object_without_field(
          parse_wire(artifact.wire, limits()).unwrap(),
          "checkpoint_cid",
        ).unwrap(),
      ).unwrap() {
      map[field.0] = to_json(field.1)
    }
    map
  }
  let with_run = body(prep)
  with_run["run_id"] = Json::string("run-1")
  assert_eq(
    seal_checkpoint_body(Json::object(with_run).stringify(), limits()).map(_ => {
      ()
    }),
    Err(UnknownField("run_id")),
  )
  let with_definition = body(prep)
  with_definition["run_definition_cid"] = Json::string(cid("1"))
  assert_eq(
    seal_checkpoint_body(Json::object(with_definition).stringify(), limits()).map(_ => {
        ()
      },
    ),
    Err(UnknownField("run_definition_cid")),
  )
  let missing = body(unit)
  missing.remove("run_definition_cid")
  assert_eq(
    seal_checkpoint_body(Json::object(missing).stringify(), limits()).map(_ => {
      ()
    }),
    Err(MissingField("run_definition_cid")),
  )
  let foreign = body(unit)
  foreign["run_id"] = Json::string("run-2")
  assert_eq(
    seal_checkpoint_body(Json::object(foreign).stringify(), limits()).map(_ => {
      ()
    }),
    Err(InvalidField("subject.run_id")),
  )
  // A preparation Checkpoint precedes its Run: there is no waiting Run state.
  let persisted = confirm_checkpoint_persisted(prep, prep.wire).unwrap()
  assert_eq(
    issue_waiting_run_state(
      persisted,
      "2026-09-25T10:00:00.000Z",
      ["tickets"],
      limits(),
    ),
    Err(RunStateInvalidField("checkpoint.subject")),
  )
}

///|
test "a resolution binds preparation or run identity by subject" {
  let prep = sealed_of(run_scope_request())
  let evidence = run_scope_evidence(prep)
  let evidence_cid = Some(canonical_cid(evidence))
  let good = resolution_fields_for(prep, "approved", evidence_cid)
  assert_true(!good.contains("run_id"))
  assert_true(
    admit(prep, with_self_cid(good, "resolution_cid"), Some(evidence)) is Ok(_),
  )
  for field in ["run_id", "run_definition_cid"] {
    let fields = resolution_fields_for(prep, "approved", evidence_cid)
    fields[field] = Json::string(
      if field == "run_id" {
        "run-1"
      } else {
        cid("1")
      },
    )
    assert_eq(
      issue_of(
        admit(prep, with_self_cid(fields, "resolution_cid"), Some(evidence)),
      ),
      Some(CheckpointBindingMismatch(field)),
    )
  }
  let missing = resolution_fields_for(prep, "approved", evidence_cid)
  missing.remove("prepare_attempt_id")
  assert_eq(
    issue_of(
      admit(prep, with_self_cid(missing, "resolution_cid"), Some(evidence)),
    ),
    Some(ResolutionMissingField("prepare_attempt_id")),
  )
  let other = resolution_fields_for(prep, "approved", evidence_cid)
  other["prepare_attempt_id"] = Json::string("attempt-2")
  assert_eq(
    issue_of(
      admit(prep, with_self_cid(other, "resolution_cid"), Some(evidence)),
    ),
    Some(CheckpointBindingMismatch("prepare_attempt_id")),
  )
  let unit = sealed_of(effect_request())
  let unit_fields = resolution_fields_for(unit, "rejected", None)
  unit_fields["prepare_attempt_id"] = Json::string("attempt-1")
  assert_eq(
    issue_of(admit(unit, with_self_cid(unit_fields, "resolution_cid"), None)),
    Some(CheckpointBindingMismatch("prepare_attempt_id")),
  )
  let unit_missing = resolution_fields_for(unit, "rejected", None)
  unit_missing.remove("run_definition_cid")
  assert_eq(
    issue_of(admit(unit, with_self_cid(unit_missing, "resolution_cid"), None)),
    Some(ResolutionMissingField("run_definition_cid")),
  )
}

///|
test "resolution proof preimage is the unsigned resolution cid text" {
  let checkpoint = sealed_of(effect_request())
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "rejected", None),
    "resolution_cid",
  )
  let value = parse_wire(resolution, limits()).unwrap()
  let unsigned = @json.object_without_field(
    @json.object_without_field(value, "resolution_cid").unwrap(),
    "proof",
  ).unwrap()
  assert_eq(
    resolution_proof_preimage(resolution, limits()),
    Ok(cid_of(unsigned, limits()).unwrap()),
  )
  assert_eq(
    resolution_proof_preimage(checkpoint.wire, limits()),
    Err(ResolutionInvalidField("version")),
  )
  assert_eq(
    resolution_proof_preimage(
      Json::object(resolution_fields_for(checkpoint, "rejected", None)).stringify(),
      limits(),
    ),
    Err(ResolutionMissingField("resolution_cid")),
  )
}

///|
test "resolution effect depends on the checkpoint subject" {
  let prep = sealed_of(run_scope_request())
  let unit = sealed_of(effect_request())
  assert_eq(resolution_effect(unit, Approved), MoveRun(Resuming))
  assert_eq(resolution_effect(unit, Rejected), MoveRun(Cancelled))
  assert_eq(resolution_effect(prep, Approved), ContinuePreparation)
  assert_eq(resolution_effect(prep, Rejected), EndPreparation)
  // Earlier Effect outcomes still unknown: a rejection does not hide them.
  assert_eq(
    resolution_effect(unit, Rejected, unknown_effects=["effect-1"]),
    MoveRun(NeedsReconciliation),
  )
  assert_eq(
    resolution_effect(unit, Approved, unknown_effects=["effect-1"]),
    MoveRun(Resuming),
  )
  assert_eq(
    resolution_effect(prep, Rejected, unknown_effects=["effect-1"]),
    EndPreparation,
  )
}

///|
test "a rejected, expired or cancelled wait preserves unknown Effect outcomes" {
  assert_eq(waiting_exit_status([]), Cancelled)
  assert_eq(waiting_exit_status(["effect-1"]), NeedsReconciliation)
  assert_true(
    run_transition_allowed(WaitingCheckpoint, waiting_exit_status([])),
  )
  assert_true(
    run_transition_allowed(WaitingCheckpoint, waiting_exit_status(["e"])),
  )
  let cancelled = issue_waiting_exit_run_state(
    "run-1",
    "2026-09-25T13:00:00.000Z",
    ["tickets"],
    [],
    limits(),
  ).unwrap()
  assert_true(cancelled.contains("\"next_action\":{\"kind\":\"none\"}"))
  assert_true(!cancelled.contains("terminal_error"))
  assert_eq(
    admit_run_state_wire(cancelled, limits()).unwrap().status,
    Cancelled,
  )
  let unknown = issue_waiting_exit_run_state(
    "run-1",
    "2026-09-25T13:00:00.000Z",
    ["tickets"],
    ["effect-2", "effect-1"],
    limits(),
  ).unwrap()
  assert_true(
    unknown.contains(
      "\"next_action\":{\"effects\":[\"effect-2\",\"effect-1\"],\"kind\":\"reconcile\"}",
    ),
  )
  let view = admit_run_state_wire(unknown, limits()).unwrap()
  assert_eq(view.status, NeedsReconciliation)
  assert_eq(view.checkpoint_cid, None)
  assert_eq(
    issue_waiting_exit_run_state(
      "run-1",
      "2026-09-25T13:00:00.000Z",
      ["tickets"],
      ["effect-1", "effect-1"],
      limits(),
    ),
    Err(RunStateInvalidField("next_action.effects")),
  )
}

///|
test "an immediate answer is validated like a deferred one but is never persistable" {
  let request = effect_request()
  let subject = sealed_of(request)
  let evidence = effect_evidence(
    subject,
    ["effect_scope_approved", "partial_application_accepted"],
    "alice",
  )
  let resolution = with_self_cid(
    resolution_fields_for(subject, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  let immediate = admit_immediate_resolution(
    request,
    resolution,
    Some(evidence),
    authentication(resolution),
    authorities(),
    "2026-09-25T12:00:01.000Z",
    limits(),
  ).unwrap()
  assert_eq(immediate.checkpoint_cid(), subject.checkpoint_cid)
  assert_eq(immediate.decision(), Approved)
  let deferred = admit(subject, resolution, Some(evidence)).unwrap()
  assert_eq(immediate.resolution_cid(), deferred.resolution_cid)
  assert_eq(immediate.attestation_preimage(), deferred.attestation_preimage)
  let answered = seal_immediate_resolution(
    immediate,
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  let verified = seal_verified_resolution(
    deferred,
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  // Same decision evidence as the deferred path, without a resume intent.
  assert_eq(answered.wire, verified.wire)
  assert_eq(answered.verified_resolution_cid, verified.verified_resolution_cid)
  assert_eq(answered.checkpoint_cid, subject.checkpoint_cid)
  // A different would-be body is a different subject.
  let other = { ..request, review_projection_cid: cid("9"), }
  assert_eq(
    admit_immediate_resolution(
      other,
      resolution,
      Some(evidence),
      authentication(resolution),
      authorities(),
      "2026-09-25T12:00:01.000Z",
      limits(),
    ).map(_ => ()),
    Err(CheckpointBindingMismatch("checkpoint_cid")),
  )
  let invalid = { ..request, requirements: [], }
  assert_eq(
    admit_immediate_resolution(
      invalid,
      resolution,
      Some(evidence),
      authentication(resolution),
      authorities(),
      "2026-09-25T12:00:01.000Z",
      limits(),
    ).map(_ => ()),
    Err(ResolutionInvalidField("checkpoint")),
  )
  let early = admit_immediate_resolution(
    request,
    resolution,
    Some(evidence),
    authentication(resolution),
    authorities(),
    "2026-09-25T11:59:59.000Z",
    limits(),
  )
  assert_eq(early.map(_ => ()), Err(DecisionAfterVerification))
}

///|
test "failed resume revalidation ends the run with its terminal error" {
  let failed = issue_revalidation_failed_run_state(
    "run-1",
    "2026-09-25T13:00:00.000Z",
    ["tickets"],
    [],
    limits(),
  ).unwrap()
  assert_true(
    failed.contains(
      "\"terminal_error\":{\"code\":\"ACTQL_E_RESUME_REVALIDATION_FAILED\"",
    ),
  )
  let view = admit_run_state_wire(failed, limits()).unwrap()
  assert_eq(view.status, Failed)
  let unknown = issue_revalidation_failed_run_state(
    "run-1",
    "2026-09-25T13:00:00.000Z",
    ["tickets"],
    ["effect-2", "effect-1"],
    limits(),
  ).unwrap()
  assert_true(
    unknown.contains(
      "\"next_action\":{\"effects\":[\"effect-2\",\"effect-1\"],\"kind\":\"reconcile\"}",
    ),
  )
  assert_eq(
    admit_run_state_wire(unknown, limits()).unwrap().status,
    NeedsReconciliation,
  )
  assert_eq(
    issue_revalidation_failed_run_state(
      "run-1",
      "2026-09-25T13:00:00.000Z",
      ["tickets"],
      ["effect-1", "effect-1"],
      limits(),
    ),
    Err(RunStateInvalidField("next_action.effects")),
  )
  assert_eq(revalidation_failure_status([]), Failed)
  assert_true(run_transition_allowed(Resuming, revalidation_failure_status([])))
  assert_true(
    run_transition_allowed(Resuming, revalidation_failure_status(["e"])),
  )
}

///|
test "a resumed approval reports only evidence claims and its own lifetime" {
  let checkpoint = sealed_of(run_scope_request())
  let evidence = run_scope_evidence(checkpoint)
  let resolution = with_self_cid(
    resolution_fields_for(checkpoint, "approved", Some(canonical_cid(evidence))),
    "resolution_cid",
  )
  let verified = seal_verified_resolution(
    admit(checkpoint, resolution, Some(evidence)).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  let approval = resumed_approval(verified.wire, limits()).unwrap()
  assert_eq(approval.checkpoint_cid, checkpoint.checkpoint_cid)
  assert_eq(approval.resolution_cid, verified.resolution_cid)
  assert_eq(approval.verified_resolution_cid, verified.verified_resolution_cid)
  assert_eq(approval.reviewer_id, "alice")
  assert_eq(approval.claims, ["invocation_scope_approved"])
  assert_eq(approval.expires_at, Some("2026-09-26T10:00:00.000Z"))
  assert_true(resumed_approval_current(approval, "2026-09-26T09:59:59.999Z"))
  // The exact expiry instant no longer authorizes new work.
  assert_true(!resumed_approval_current(approval, "2026-09-26T10:00:00.000Z"))
  assert_true(!resumed_approval_current(approval, "2026-09-27T00:00:00.000Z"))
  assert_true(!resumed_approval_current(approval, "not a time"))
  // An Effect Set attestation establishes its carried claims and no expiry.
  let (effect, effect_resolution, effect_evidence) = approved_effect()
  let attested = seal_verified_resolution(
    admit(effect, effect_resolution, Some(effect_evidence)).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  let effect_approval = resumed_approval(attested.wire, limits()).unwrap()
  assert_eq(effect_approval.claims, [
    "effect_scope_approved", "partial_application_accepted",
  ])
  assert_eq(effect_approval.expires_at, None)
  // A rejection or an altered wrapper grants nothing.
  let rejection = with_self_cid(
    resolution_fields_for(checkpoint, "rejected", None),
    "resolution_cid",
  )
  let rejected = seal_verified_resolution(
    admit(checkpoint, rejection, None).unwrap(),
    "host-key",
    "aG9zdA==",
    limits(),
  ).unwrap()
  assert_eq(
    issue_of(resumed_approval(rejected.wire, limits())),
    Some(ResolutionInvalidField("resolution.decision")),
  )
  assert_eq(
    issue_of(
      resumed_approval(
        verified.wire.replace(
          old="invocation_scope_approved",
          new="host-required-risk",
        ),
        limits(),
      ),
    ),
    Some(ResolutionIdentityMismatch),
  )
}
