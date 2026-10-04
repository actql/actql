///|
/// Every export returns one JSON text: `{"ok":true,...}` or
/// `{"ok":false,"issue":"stable-code","detail":"diagnostic"}`.
/// The adapter never decides semantics.
fn limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 1048576, max_nodes: 65536, max_depth: 64, }
}

///|
fn ok(fields : Map[String, Json]) -> String {
  fields["ok"] = Json::boolean(true)
  Json::object(fields).stringify()
}

///|
fn fail(issue : String) -> String {
  Json::object({ "ok": Json::boolean(false), "issue": Json::string(issue) }).stringify()
}

///|
fn fail_detail(issue : String, detail : String) -> String {
  Json::object({
    "ok": Json::boolean(false),
    "issue": Json::string(issue),
    "detail": Json::string(detail),
  }).stringify()
}

///|
priv struct BridgeFailure {
  code : String
  detail : String
}

///|
fn bridge_failure(code : String, detail : String) -> BridgeFailure {
  { code, detail, }
}

///|
fn checkpoint_issue_code(issue : @checkpoint.CheckpointIssue) -> String {
  match issue {
    InvalidLimits => "InvalidLimits"
    InvalidWire => "InvalidWire"
    InvalidObject => "InvalidObject"
    MissingField(_) => "MissingField"
    UnknownField(_) => "UnknownField"
    InvalidField(_) => "InvalidField"
    UnsupportedCombination => "UnsupportedCombination"
    InvalidRequirements => "InvalidRequirements"
    InvalidTimeWindow => "InvalidTimeWindow"
    IdentityMismatch => "IdentityMismatch"
    PersistedWireMismatch => "PersistedWireMismatch"
    Encoding => "Encoding"
  }
}

///|
fn resolution_issue_code(issue : @checkpoint.ResolutionIssue) -> String {
  match issue {
    ResolutionInvalidLimits => "ResolutionInvalidLimits"
    ResolutionInvalidWire => "ResolutionInvalidWire"
    ResolutionInvalidObject => "ResolutionInvalidObject"
    ResolutionMissingField(_) => "ResolutionMissingField"
    ResolutionUnknownField(_) => "ResolutionUnknownField"
    ResolutionInvalidField(_) => "ResolutionInvalidField"
    ResolutionIdentityMismatch => "ResolutionIdentityMismatch"
    CheckpointBindingMismatch(_) => "CheckpointBindingMismatch"
    DecisionOutsideWindow => "DecisionOutsideWindow"
    DecisionAfterVerification => "DecisionAfterVerification"
    EvidenceRequired => "EvidenceRequired"
    EvidenceForbidden => "EvidenceForbidden"
    EvidenceMismatch(_) => "EvidenceMismatch"
    AuthenticationMismatch(_) => "AuthenticationMismatch"
    AuthorityNotPermitted => "AuthorityNotPermitted"
    InvalidAttestation => "InvalidAttestation"
    ResolutionEncoding => "ResolutionEncoding"
  }
}

///|
fn resume_issue_code(issue : @checkpoint.ResumeIssue) -> String {
  match issue {
    InvalidClaimant => "InvalidClaimant"
    InvalidLease => "InvalidLease"
    InvalidClock => "InvalidClock"
    InvalidBinding => "InvalidBinding"
    InvalidIntent => "InvalidIntent"
  }
}

///|
fn run_state_issue_code(issue : @checkpoint.RunStateWireIssue) -> String {
  match issue {
    RunStateInvalidWire => "RunStateInvalidWire"
    RunStateInvalidField(_) => "RunStateInvalidField"
    RunStateUnknownField(_) => "RunStateUnknownField"
    RunStateMissingField(_) => "RunStateMissingField"
    RunStateRelation(_) => "RunStateRelation"
    RunStateEncoding => "RunStateEncoding"
  }
}

///|
fn fail_checkpoint(issue : @checkpoint.CheckpointIssue) -> String {
  fail_detail(checkpoint_issue_code(issue), @debug.to_string(issue))
}

///|
fn fail_resolution(issue : @checkpoint.ResolutionIssue) -> String {
  fail_detail(resolution_issue_code(issue), @debug.to_string(issue))
}

///|
fn fail_resume(issue : @checkpoint.ResumeIssue) -> String {
  fail_detail(resume_issue_code(issue), @debug.to_string(issue))
}

///|
fn fail_run_state(issue : @checkpoint.RunStateWireIssue) -> String {
  fail_detail(run_state_issue_code(issue), @debug.to_string(issue))
}

///|
fn optional_text(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn parse(text : String) -> Json? {
  Some(@core_json.parse(text)) catch {
    _ => None
  }
}

///|
fn text_member(value : Json, key : String) -> String? {
  match value {
    Object(map) =>
      match map.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn number_member(value : Json, key : String) -> Double? {
  match value {
    Object(map) =>
      match map.get(key) {
        Some(Number(number, ..)) => Some(number)
        _ => None
      }
    _ => None
  }
}

///|
fn text_list(text : String) -> Array[String]? {
  match parse(text) {
    Some(Array(items)) => {
      let result : Array[String] = []
      for item in items {
        match item {
          String(value) => result.push(value)
          _ => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn safe_integer(value : Double) -> Int64? {
  if value != value.floor() ||
    value < -9007199254740991.0 ||
    value > 9007199254740991.0 {
    None
  } else {
    Some(value.to_int64())
  }
}

///|
fn checkpoint_fields(
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Map[String, Json] {
  let request = checkpoint.checkpoint
  let (subject_kind, unit) = match request.subject {
    PrepareAttempt(..) => ("prepare_attempt", None)
    RunUnit(unit_id~, ..) => ("run_unit", Some(unit_id))
  }
  {
    "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
    "checkpoint_wire": Json::string(checkpoint.wire),
    "checkpoint_id": Json::string(request.checkpoint_id),
    "run_id": optional_text(request.run_id()),
    "kind": Json::string(@checkpoint.checkpoint_kind_token(request.kind)),
    "subject_kind": Json::string(subject_kind),
    "prepare_attempt_id": optional_text(request.prepare_attempt_id()),
    "unit_id": optional_text(unit),
    "created_at": Json::string(request.created_at),
    "expires_at": Json::string(request.expires_at),
  }
}

///|
#export_name("checkpointSealBody")
pub fn checkpoint_seal_body(body_wire : String) -> String {
  match @checkpoint.seal_checkpoint_body(body_wire, limits()) {
    Ok(checkpoint) => ok(checkpoint_fields(checkpoint))
    Err(issue) => fail_checkpoint(issue)
  }
}

///|
#export_name("checkpointAdmit")
pub fn checkpoint_admit(wire : String) -> String {
  match @checkpoint.admit_checkpoint_wire(wire, limits()) {
    Ok(checkpoint) => ok(checkpoint_fields(checkpoint))
    Err(issue) => fail_checkpoint(issue)
  }
}

///|
/// Waiting projection from the exact wire read back after commit.
#export_name("checkpointWaitingState")
pub fn checkpoint_waiting_state(
  sealed_wire : String,
  stored_wire : String,
  updated_at : String,
  declared_results_json : String,
) -> String {
  let checkpoint = match
    @checkpoint.admit_checkpoint_wire(sealed_wire, limits()) {
    Ok(value) => value
    Err(issue) => return fail_checkpoint(issue)
  }
  let persisted = match
    @checkpoint.confirm_checkpoint_persisted(checkpoint, stored_wire) {
    Ok(value) => value
    Err(issue) => return fail_checkpoint(issue)
  }
  let declared = match text_list(declared_results_json) {
    Some(values) => values
    None => return fail("InvalidDeclaredResults")
  }
  match
    @checkpoint.issue_waiting_run_state(
      persisted,
      updated_at,
      declared,
      limits(),
    ) {
    Ok(wire) => ok({ "run_state_wire": Json::string(wire) })
    Err(issue) => fail_run_state(issue)
  }
}

///|
#export_name("checkpointLifecycleState")
pub fn checkpoint_lifecycle_state(
  run_id : String,
  status : String,
  updated_at : String,
  declared_results_json : String,
) -> String {
  let parsed = match @checkpoint.parse_run_status(status) {
    Some(value) => value
    None => return fail("InvalidStatus")
  }
  let declared = match text_list(declared_results_json) {
    Some(values) => values
    None => return fail("InvalidDeclaredResults")
  }
  match
    @checkpoint.issue_lifecycle_run_state(
      run_id,
      parsed,
      updated_at,
      declared,
      limits(),
    ) {
    Ok(wire) => ok({ "run_state_wire": Json::string(wire) })
    Err(issue) => fail_run_state(issue)
  }
}

///|
#export_name("runStateAdmit")
pub fn run_state_admit(wire : String) -> String {
  match @checkpoint.admit_run_state_wire(wire, limits()) {
    Ok(view) =>
      ok({
        "run_id": Json::string(view.run_id),
        "status": Json::string(@checkpoint.run_status_token(view.status)),
        "checkpoint_cid": optional_text(view.checkpoint_cid),
        "run_state_wire": Json::string(view.wire),
      })
    Err(issue) => fail_run_state(issue)
  }
}

///|
#export_name("runOutcomeTerminal")
pub fn run_outcome_terminal(status : String) -> Bool {
  match @checkpoint.parse_run_status(status) {
    Some(outcome) => @checkpoint.run_outcome_terminal(outcome)
    None => false
  }
}

///|
#export_name("runTransitionAllowed")
pub fn run_transition_allowed(from : String, to : String) -> Bool {
  match (@checkpoint.parse_run_status(from), @checkpoint.parse_run_status(to)) {
    (Some(left), Some(right)) => @checkpoint.run_transition_allowed(left, right)
    _ => false
  }
}

///|
#export_name("resumeCompletionAllowed")
pub fn resume_completion_allowed(to : String) -> Bool {
  match @checkpoint.parse_run_status(to) {
    Some(status) => @checkpoint.resume_completion_allowed(status)
    None => false
  }
}

///|
#export_name("checkpointExpiredAt")
pub fn checkpoint_expired_at(checkpoint_wire : String, now : String) -> String {
  let checkpoint = match
    @checkpoint.admit_checkpoint_wire(checkpoint_wire, limits()) {
    Ok(value) => value
    Err(issue) => return fail_checkpoint(issue)
  }
  match @checkpoint.checkpoint_expired_at(checkpoint, now) {
    Ok(expired) => ok({ "expired": Json::boolean(expired) })
    Err(issue) => fail_checkpoint(issue)
  }
}

///|
fn authentication(text : String) -> @checkpoint.HostAuthentication? {
  let value = match parse(text) {
    Some(value) => value
    None => return None
  }
  match
    (
      text_member(value, "key_id"),
      text_member(value, "reviewer_id"),
      text_member(value, "expected_authority_scope_cid"),
      text_member(value, "authority_context_cid"),
      text_member(value, "policy_cid"),
      text_member(value, "proof_preimage"),
    ) {
    (
      Some(key_id),
      Some(reviewer_id),
      Some(expected_authority_scope_cid),
      Some(authority_context_cid),
      Some(policy_cid),
      Some(proof_preimage),
    ) =>
      Some({
        key_id,
        reviewer_id,
        expected_authority_scope_cid,
        authority_context_cid,
        policy_cid,
        proof_preimage,
      })
    _ => None
  }
}

///|
fn authorities(text : String) -> Array[@checkpoint.ReviewerAuthority]? {
  match parse(text) {
    Some(Array(items)) => {
      let result : Array[@checkpoint.ReviewerAuthority] = []
      for item in items {
        match (text_member(item, "key_id"), text_member(item, "reviewer_id")) {
          (Some(key_id), Some(reviewer_id)) =>
            result.push({ key_id, reviewer_id, })
          _ => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn admit_resolution(
  checkpoint_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
) -> Result[
  (@checkpoint.SealedCheckpoint, @checkpoint.AdmittedResolution),
  BridgeFailure,
] {
  let checkpoint = match
    @checkpoint.admit_checkpoint_wire(checkpoint_wire, limits()) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        bridge_failure(checkpoint_issue_code(issue), @debug.to_string(issue)),
      )
  }
  let auth = match authentication(authentication_json) {
    Some(value) => value
    None =>
      return Err(
        bridge_failure("InvalidAuthentication", "InvalidAuthentication"),
      )
  }
  let allowed = match authorities(authorities_json) {
    Some(value) => value
    None =>
      return Err(bridge_failure("InvalidAuthorities", "InvalidAuthorities"))
  }
  let evidence = if evidence_wire == "" { None } else { Some(evidence_wire) }
  match
    @checkpoint.admit_checkpoint_resolution(
      checkpoint,
      resolution_wire,
      evidence,
      auth,
      allowed,
      verified_at,
      limits(),
    ) {
    Ok(admitted) => Ok((checkpoint, admitted))
    Err(issue) =>
      Err(bridge_failure(resolution_issue_code(issue), @debug.to_string(issue)))
  }
}

///|
fn decision_token(decision : @checkpoint.ResolutionDecision) -> String {
  match decision {
    Approved => "approved"
    Rejected => "rejected"
  }
}

///|
/// Admission before Host attestation; returns the canonical preimage the Host
/// signs. `evidence_wire` is empty when no approval evidence is supplied.
#export_name("resolutionAdmit")
pub fn resolution_admit(
  checkpoint_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
) -> String {
  match
    admit_resolution(
      checkpoint_wire, resolution_wire, evidence_wire, authentication_json, authorities_json,
      verified_at,
    ) {
    Ok((_, admitted)) =>
      ok({
        "resolution_id": Json::string(admitted.resolution_id),
        "resolution_cid": Json::string(admitted.resolution_cid),
        "decision": Json::string(decision_token(admitted.decision)),
        "attestation_preimage": Json::string(admitted.attestation_preimage),
      })
    Err(issue) => fail_detail(issue.code, issue.detail)
  }
}

///|
fn closure(
  state : String,
  resolution_cid : String,
) -> @checkpoint.CheckpointClosure? {
  match state {
    "open" => Some(Open)
    "resolved" => Some(Resolved(resolution_cid))
    "expired" => Some(Expired)
    _ => None
  }
}

///|
fn commit_action(action : @checkpoint.ResolutionCommitAction) -> String {
  match action {
    CommitResolution => "commit"
    DuplicateResolution => "duplicate"
    ConflictingResolution => "conflict"
    CheckpointExpired => "expired"
  }
}

///|
/// Re-admit deterministically, attach the Host attestation, and decide the
/// commit against the closure read inside the store transaction.
#export_name("resolutionDecide")
pub fn resolution_decide(
  checkpoint_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
  host_key_id : String,
  signature : String,
  closure_state : String,
  closure_resolution_cid : String,
  unknown_effects_json : String,
) -> String {
  let unknown = match text_list(unknown_effects_json) {
    Some(values) => values
    None => return fail("InvalidUnknownEffects")
  }
  let (checkpoint, admitted) = match
    admit_resolution(
      checkpoint_wire, resolution_wire, evidence_wire, authentication_json, authorities_json,
      verified_at,
    ) {
    Ok(value) => value
    Err(issue) => return fail_detail(issue.code, issue.detail)
  }
  let verified = match
    @checkpoint.seal_verified_resolution(
      admitted,
      host_key_id,
      signature,
      limits(),
    ) {
    Ok(value) => value
    Err(issue) => return fail_resolution(issue)
  }
  let current = match closure(closure_state, closure_resolution_cid) {
    Some(value) => value
    None => return fail("InvalidClosure")
  }
  let action = @checkpoint.decide_resolution_commit(
    checkpoint, current, verified,
  )
  let (effect, run_status) = match
    @checkpoint.resolution_effect(
      checkpoint,
      verified.decision,
      unknown_effects=unknown,
    ) {
    MoveRun(status) =>
      ("move_run", Json::string(@checkpoint.run_status_token(status)))
    ContinuePreparation => ("continue_preparation", Json::null())
    EndPreparation => ("end_preparation", Json::null())
  }
  ok({
    "action": Json::string(commit_action(action)),
    "decision": Json::string(decision_token(verified.decision)),
    "effect": Json::string(effect),
    "run_status": run_status,
    "resolution_id": Json::string(verified.resolution_id),
    "resolution_cid": Json::string(verified.resolution_cid),
    "verified_resolution_cid": Json::string(verified.verified_resolution_cid),
    "verified_resolution_wire": Json::string(verified.wire),
    "resume_intent_id": optional_text(verified.resume_intent_id),
  })
}

///|
fn intent_view(text : String) -> @checkpoint.ResumeIntentView? {
  let value = match parse(text) {
    Some(value) => value
    None => return None
  }
  let state : @checkpoint.ResumeIntentState = match
    text_member(value, "state") {
    Some("pending") => ResumePending
    Some("claimed") => ResumeClaimed
    Some("completed") => ResumeCompleted
    _ => return None
  }
  let generation = match number_member(value, "generation") {
    Some(number) => safe_integer(number)
    None => None
  }
  let lease = match number_member(value, "lease_expires_ms") {
    Some(number) => safe_integer(number)
    None => None
  }
  match (generation, lease, text_member(value, "claimant")) {
    (Some(generation), Some(lease_expires_ms), Some(claimant)) =>
      Some({ state, generation, claimant, lease_expires_ms, })
    _ => None
  }
}

///|
fn binding(text : String) -> @checkpoint.ResumeBinding? {
  let value = match parse(text) {
    Some(value) => value
    None => return None
  }
  match
    (
      text_member(value, "authorization_context_cid"),
      text_member(value, "environment_binding_cid"),
    ) {
    (Some(authorization_context_cid), Some(environment_binding_cid)) =>
      Some({ authorization_context_cid, environment_binding_cid, })
    _ => None
  }
}

///|
#export_name("resumeClaimDecide")
pub fn resume_claim_decide(
  intent_json : String,
  claimant : String,
  now_ms : Double,
  lease_ms : Double,
  bound_json : String,
  current_json : String,
) -> String {
  let intent = match intent_view(intent_json) {
    Some(value) => value
    None => return fail("InvalidIntent")
  }
  let (now, lease) = match (safe_integer(now_ms), safe_integer(lease_ms)) {
    (Some(now), Some(lease)) => (now, lease)
    _ => return fail("InvalidClock")
  }
  let (bound, current) = match (binding(bound_json), binding(current_json)) {
    (Some(bound), Some(current)) => (bound, current)
    _ => return fail("InvalidBinding")
  }
  match
    @checkpoint.decide_resume_claim(
      intent, claimant, now, lease, bound, current,
    ) {
    Ok(ClaimIntent(generation, expires)) =>
      ok({
        "action": Json::string("claim"),
        "generation": Json::number(generation.to_double()),
        "lease_expires_ms": Json::number(expires.to_double()),
      })
    Ok(ClaimBusy) => ok({ "action": Json::string("busy") })
    Ok(ClaimCompleted) => ok({ "action": Json::string("completed") })
    Ok(ClaimInvalidated(generation)) =>
      ok({
        "action": Json::string("invalidated"),
        "generation": Json::number(generation.to_double()),
        "run_status": Json::string("failed"),
      })
    Err(issue) => fail_resume(issue)
  }
}

///|
#export_name("resumeFenceDecide")
pub fn resume_fence_decide(
  intent_json : String,
  claimant : String,
  generation : Double,
  now_ms : Double,
) -> String {
  let intent = match intent_view(intent_json) {
    Some(value) => value
    None => return fail("InvalidIntent")
  }
  let (claim_generation, now) = match
    (safe_integer(generation), safe_integer(now_ms)) {
    (Some(claim_generation), Some(now)) => (claim_generation, now)
    _ => return fail("InvalidClock")
  }
  let action = @checkpoint.decide_resume_fence(
    intent,
    { claimant, generation: claim_generation, },
    now,
  )
  match action {
    FenceCurrent => ok({ "action": Json::string("current") })
    FenceStale => ok({ "action": Json::string("stale") })
  }
}

///|
/// Permission of one committed approved verified Resolution at the Host
/// trusted time `at`: the claims its evidence establishes, its expiry (null
/// when the evidence carries none) and whether it is still current.
#export_name("resumedApprovalAt")
pub fn resumed_approval_at(verified_wire : String, at : String) -> String {
  match @checkpoint.resumed_approval(verified_wire, limits()) {
    Ok(approval) =>
      ok({
        "checkpoint_cid": Json::string(approval.checkpoint_cid),
        "resolution_cid": Json::string(approval.resolution_cid),
        "verified_resolution_cid": Json::string(
          approval.verified_resolution_cid,
        ),
        "reviewer_id": Json::string(approval.reviewer_id),
        "claims": Json::array(approval.claims.map(claim => Json::string(claim))),
        "expires_at": optional_text(approval.expires_at),
        "current": Json::boolean(
          @checkpoint.resumed_approval_current(approval, at),
        ),
      })
    Err(issue) => fail_resolution(issue)
  }
}

///|
/// Unsigned Resolution CID text: the exact UTF-8 text whose Ed25519
/// `proof.signature` the Host authorization port verifies.
#export_name("resolutionProofPreimage")
pub fn resolution_proof_preimage(resolution_wire : String) -> String {
  match @checkpoint.resolution_proof_preimage(resolution_wire, limits()) {
    Ok(preimage) => ok({ "preimage": Json::string(preimage) })
    Err(issue) => fail_resolution(issue)
  }
}

///|
/// Unsigned verified-wrapper CID text: the exact UTF-8 text whose Ed25519
/// `host_attestation.signature` the Host produces and verifiers check.
#export_name("verifiedAttestationPreimage")
pub fn verified_attestation_preimage(verified_wire : String) -> String {
  match
    @checkpoint.verified_resolution_attestation_preimage(
      verified_wire,
      limits(),
    ) {
    Ok(preimage) => ok({ "preimage": Json::string(preimage) })
    Err(issue) => fail_resolution(issue)
  }
}

///|
fn admit_immediate(
  body_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
) -> Result[@checkpoint.ImmediateAdmittedResolution, BridgeFailure] {
  let subject = match @checkpoint.seal_checkpoint_body(body_wire, limits()) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        bridge_failure(checkpoint_issue_code(issue), @debug.to_string(issue)),
      )
  }
  let auth = match authentication(authentication_json) {
    Some(value) => value
    None =>
      return Err(
        bridge_failure("InvalidAuthentication", "InvalidAuthentication"),
      )
  }
  let allowed = match authorities(authorities_json) {
    Some(value) => value
    None =>
      return Err(bridge_failure("InvalidAuthorities", "InvalidAuthorities"))
  }
  let evidence = if evidence_wire == "" { None } else { Some(evidence_wire) }
  match
    @checkpoint.admit_immediate_resolution(
      subject.checkpoint,
      resolution_wire,
      evidence,
      auth,
      allowed,
      verified_at,
      limits(),
    ) {
    Ok(admitted) => Ok(admitted)
    Err(issue) =>
      Err(bridge_failure(resolution_issue_code(issue), @debug.to_string(issue)))
  }
}

///|
/// Admit an immediate delegated answer against the Checkpoint body the Host
/// would persist if it deferred. Nothing is persisted.
#export_name("resolutionAdmitImmediate")
pub fn resolution_admit_immediate(
  body_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
) -> String {
  match
    admit_immediate(
      body_wire, resolution_wire, evidence_wire, authentication_json, authorities_json,
      verified_at,
    ) {
    Ok(admitted) =>
      ok({
        "checkpoint_cid": Json::string(admitted.checkpoint_cid()),
        "resolution_cid": Json::string(admitted.resolution_cid()),
        "decision": Json::string(decision_token(admitted.decision())),
        "attestation_preimage": Json::string(admitted.attestation_preimage()),
      })
    Err(issue) => fail_detail(issue.code, issue.detail)
  }
}

///|
/// Re-admit deterministically and attach the Host attestation. The result is
/// the retained decision evidence; it has no resume intent.
#export_name("resolutionSealImmediate")
pub fn resolution_seal_immediate(
  body_wire : String,
  resolution_wire : String,
  evidence_wire : String,
  authentication_json : String,
  authorities_json : String,
  verified_at : String,
  host_key_id : String,
  signature : String,
) -> String {
  let admitted = match
    admit_immediate(
      body_wire, resolution_wire, evidence_wire, authentication_json, authorities_json,
      verified_at,
    ) {
    Ok(value) => value
    Err(issue) => return fail_detail(issue.code, issue.detail)
  }
  match
    @checkpoint.seal_immediate_resolution(
      admitted,
      host_key_id,
      signature,
      limits(),
    ) {
    Ok(immediate) =>
      ok({
        "checkpoint_cid": Json::string(immediate.checkpoint_cid),
        "decision": Json::string(decision_token(immediate.decision)),
        "resolution_cid": Json::string(immediate.resolution_cid),
        "verified_resolution_cid": Json::string(
          immediate.verified_resolution_cid,
        ),
        "verified_resolution_wire": Json::string(immediate.wire),
      })
    Err(issue) => fail_resolution(issue)
  }
}

///|
/// Run state of a Run-unit continuation that failed resume revalidation:
/// `failed`, or `needs_reconciliation` over the unknown Effects, with
/// `terminal_error.code` `ACTQL_E_RESUME_REVALIDATION_FAILED`.
#export_name("revalidationFailedState")
pub fn revalidation_failed_state(
  run_id : String,
  updated_at : String,
  declared_results_json : String,
  unknown_effects_json : String,
) -> String {
  let declared = match text_list(declared_results_json) {
    Some(values) => values
    None => return fail("InvalidDeclaredResults")
  }
  let unknown = match text_list(unknown_effects_json) {
    Some(values) => values
    None => return fail("InvalidUnknownEffects")
  }
  match
    @checkpoint.issue_revalidation_failed_run_state(
      run_id,
      updated_at,
      declared,
      unknown,
      limits(),
    ) {
    Ok(wire) =>
      ok({
        "run_status": Json::string(
          @checkpoint.run_status_token(
            @checkpoint.revalidation_failure_status(unknown),
          ),
        ),
        "terminal_error_code": Json::string(
          @checkpoint.RESUME_REVALIDATION_FAILED_CODE,
        ),
        "run_state_wire": Json::string(wire),
      })
    Err(issue) => fail_run_state(issue)
  }
}

///|
/// Run state of a waiting Run whose Checkpoint was rejected, expired or
/// cancelled without dispatch: `cancelled`, or `needs_reconciliation` over
/// the unknown Effects.
#export_name("waitingExitState")
pub fn waiting_exit_state(
  run_id : String,
  updated_at : String,
  declared_results_json : String,
  unknown_effects_json : String,
) -> String {
  let declared = match text_list(declared_results_json) {
    Some(values) => values
    None => return fail("InvalidDeclaredResults")
  }
  let unknown = match text_list(unknown_effects_json) {
    Some(values) => values
    None => return fail("InvalidUnknownEffects")
  }
  match
    @checkpoint.issue_waiting_exit_run_state(
      run_id,
      updated_at,
      declared,
      unknown,
      limits(),
    ) {
    Ok(wire) =>
      ok({
        "run_status": Json::string(
          @checkpoint.run_status_token(@checkpoint.waiting_exit_status(unknown)),
        ),
        "run_state_wire": Json::string(wire),
      })
    Err(issue) => fail_run_state(issue)
  }
}

///|
#export_name("resumeRevalidationFailedCode")
pub fn resume_revalidation_failed_code() -> String {
  @checkpoint.RESUME_REVALIDATION_FAILED_CODE
}
