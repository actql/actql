///|
const CHECKPOINT_VERSION : String = "actql-execution-checkpoint/0.1"

///|
pub fn checkpoint_kind_token(kind : CheckpointKind) -> String {
  match kind {
    RunScope => "run_scope"
    ReadAccess => "read_access"
    DataEgress => "data_egress"
    CostScope => "cost_scope"
    EffectSet => "effect_set"
  }
}

///|
pub fn parse_checkpoint_kind(token : String) -> CheckpointKind? {
  match token {
    "run_scope" => Some(RunScope)
    "read_access" => Some(ReadAccess)
    "data_egress" => Some(DataEgress)
    "cost_scope" => Some(CostScope)
    "effect_set" => Some(EffectSet)
    _ => None
  }
}

///|
fn phase_token(phase : CheckpointPhase) -> String {
  match phase {
    Preflight => "preflight"
    Commit => "commit"
  }
}

///|
fn parse_phase(token : String) -> CheckpointPhase? {
  match token {
    "preflight" => Some(Preflight)
    "commit" => Some(Commit)
    _ => None
  }
}

///|
pub fn checkpoint_requirement_token(
  requirement : CheckpointRequirement,
) -> String {
  match requirement {
    EffectScopeApproved => "effect_scope_approved"
    InvocationScopeApproved => "invocation_scope_approved"
    PartialApplicationAccepted => "partial_application_accepted"
  }
}

///|
pub fn parse_checkpoint_requirement(token : String) -> CheckpointRequirement? {
  match token {
    "effect_scope_approved" => Some(EffectScopeApproved)
    "invocation_scope_approved" => Some(InvocationScopeApproved)
    "partial_application_accepted" => Some(PartialApplicationAccepted)
    _ => None
  }
}

///|
/// The only required-artifact type for each Checkpoint kind.
pub fn checkpoint_artifact_type(kind : CheckpointKind) -> String {
  match kind {
    RunScope => "prepared_invocation"
    ReadAccess => "read_scope"
    DataEgress => "egress_scope"
    CostScope => "budget_scope"
    EffectSet => "effect_set_preview"
  }
}

///|
/// Exactly the closed subject/phase/kind table of the Run protocol.
pub fn checkpoint_combination_valid(
  subject : CheckpointSubject,
  phase : CheckpointPhase,
  kind : CheckpointKind,
) -> Bool {
  match (subject, phase, kind) {
    (PrepareAttempt(_), Preflight, RunScope) => true
    (_, Preflight, ReadAccess) => true
    (RunUnit(_, _), Preflight, DataEgress | CostScope) => true
    (RunUnit(_, _), Commit, EffectSet) => true
    _ => false
  }
}

///|
/// Requirement lists are data chosen by the Host before issuance. The core
/// enforces only the closed per-kind lists of the pinned schema: non-Effect
/// Checkpoints require exactly `[invocation_scope_approved]`; an Effect Commit
/// Checkpoint carries `[effect_scope_approved]` or
/// `[effect_scope_approved, partial_application_accepted]`.
pub fn checkpoint_requirements_valid(
  kind : CheckpointKind,
  requirements : Array[CheckpointRequirement],
) -> Bool {
  match kind {
    EffectSet =>
      requirements == [EffectScopeApproved] ||
      requirements == [EffectScopeApproved, PartialApplicationAccepted]
    _ => requirements == [InvocationScopeApproved]
  }
}

///|
fn validate_request(request : CheckpointRequest) -> CheckpointIssue? {
  if !canonical_text(request.checkpoint_id) {
    return Some(InvalidField("checkpoint_id"))
  }
  if !canonical_text(request.run_id) {
    return Some(InvalidField("run_id"))
  }
  if !valid_cid(request.run_definition_cid) {
    return Some(InvalidField("run_definition_cid"))
  }
  if !valid_cid(request.continuation_state_cid) {
    return Some(InvalidField("continuation_state_cid"))
  }
  match request.subject {
    PrepareAttempt(attempt) =>
      if !canonical_text(attempt) {
        return Some(InvalidField("subject.prepare_attempt_id"))
      }
    RunUnit(run_id, unit_id) => {
      if !canonical_text(run_id) {
        return Some(InvalidField("subject.run_id"))
      }
      if run_id != request.run_id {
        return Some(InvalidField("subject.run_id"))
      }
      if !canonical_text(unit_id) {
        return Some(InvalidField("subject.unit_id"))
      }
    }
  }
  if !checkpoint_combination_valid(request.subject, request.phase, request.kind) {
    return Some(UnsupportedCombination)
  }
  if !valid_cid(request.required_artifact_cid) {
    return Some(InvalidField("required_artifact.artifact_cid"))
  }
  if !valid_cid(request.review_projection_cid) {
    return Some(InvalidField("review_projection_cid"))
  }
  if !checkpoint_requirements_valid(request.kind, request.requirements) {
    return Some(InvalidRequirements)
  }
  if !canonical_text(request.reason_code) {
    return Some(InvalidField("reason_code"))
  }
  if !canonical_text(request.human_summary) {
    return Some(InvalidField("human_summary"))
  }
  if !valid_timestamp(request.created_at) {
    return Some(InvalidField("created_at"))
  }
  if !valid_timestamp(request.expires_at) {
    return Some(InvalidField("expires_at"))
  }
  if request.expires_at <= request.created_at {
    return Some(InvalidTimeWindow)
  }
  None
}

///|
fn subject_json(subject : CheckpointSubject) -> Json {
  match subject {
    PrepareAttempt(attempt) =>
      Json::object({
        "kind": Json::string("prepare_attempt"),
        "prepare_attempt_id": Json::string(attempt),
        "continuation": Json::string("start_run"),
      })
    RunUnit(run_id, unit_id) =>
      Json::object({
        "kind": Json::string("run_unit"),
        "run_id": Json::string(run_id),
        "unit_id": Json::string(unit_id),
        "continuation": Json::string("resume_unit"),
      })
  }
}

///|
fn request_body_json(request : CheckpointRequest) -> Json {
  Json::object({
    "version": Json::string(CHECKPOINT_VERSION),
    "checkpoint_id": Json::string(request.checkpoint_id),
    "run_id": Json::string(request.run_id),
    "run_definition_cid": Json::string(request.run_definition_cid),
    "continuation_state_cid": Json::string(request.continuation_state_cid),
    "subject": subject_json(request.subject),
    "phase": Json::string(phase_token(request.phase)),
    "kind": Json::string(checkpoint_kind_token(request.kind)),
    "required_artifact": Json::object({
      "artifact_type": Json::string(checkpoint_artifact_type(request.kind)),
      "artifact_cid": Json::string(request.required_artifact_cid),
    }),
    "review_projection_cid": Json::string(request.review_projection_cid),
    "requirements": string_array_json(
      request.requirements.map(checkpoint_requirement_token),
    ),
    "reason_code": Json::string(request.reason_code),
    "human_summary": Json::string(request.human_summary),
    "created_at": Json::string(request.created_at),
    "expires_at": Json::string(request.expires_at),
  })
}

///|
/// Build the canonical `actql-execution-checkpoint/0.1` artifact and its self
/// CID. The result is only a prepared artifact: a caller may not report a
/// waiting Checkpoint until `confirm_checkpoint_persisted` succeeds.
pub fn seal_checkpoint(
  request : CheckpointRequest,
  limits : WireLimits,
) -> Result[SealedCheckpoint, CheckpointIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  if validate_request(request) is Some(issue) {
    return Err(issue)
  }
  let body = match canonical_of(request_body_json(request), limits) {
    Some(value) => value
    None => return Err(Encoding)
  }
  let cid = match cid_of(body, limits) {
    Some(value) => value
    None => return Err(Encoding)
  }
  let complete = match
    @json.object_with_string_field(body, "checkpoint_cid", cid) {
    Some(value) => value
    None => return Err(Encoding)
  }
  let wire = match wire_of(complete, limits) {
    Some(value) => value
    None => return Err(Encoding)
  }
  Ok({ checkpoint: request, checkpoint_cid: cid, wire, })
}

///|
priv suberror CheckpointFailure {
  CheckpointFailed(CheckpointIssue)
}

///|
fn shape_issue(issue : ShapeIssue, prefix : String) -> CheckpointIssue {
  match issue {
    Unknown(key) => UnknownField(prefix + key)
    Missing(key) => MissingField(prefix + key)
    NotObject => InvalidObject
  }
}

///|
fn require_shape(
  value : @json.CanonicalValue,
  required : Array[String],
  prefix : String,
) -> Unit raise CheckpointFailure {
  if closed_shape(value, required, []) is Some(issue) {
    raise CheckpointFailed(shape_issue(issue, prefix))
  }
}

///|
fn required_text(
  value : @json.CanonicalValue,
  key : String,
) -> String raise CheckpointFailure {
  match string_field(value, key) {
    Some(text) => text
    None => raise CheckpointFailed(InvalidField(key))
  }
}

///|
fn required_object(
  value : @json.CanonicalValue,
  key : String,
) -> @json.CanonicalValue raise CheckpointFailure {
  match @json.object_field(value, key) {
    Some(item) => item
    None => raise CheckpointFailed(MissingField(key))
  }
}

///|
fn decode_subject(
  value : @json.CanonicalValue,
) -> CheckpointSubject raise CheckpointFailure {
  match string_field(value, "kind") {
    Some("prepare_attempt") => {
      require_shape(
        value,
        ["kind", "prepare_attempt_id", "continuation"],
        "subject.",
      )
      if string_field(value, "continuation") != Some("start_run") {
        raise CheckpointFailed(InvalidField("subject.continuation"))
      }
      PrepareAttempt(required_text(value, "prepare_attempt_id"))
    }
    Some("run_unit") => {
      require_shape(
        value,
        ["kind", "run_id", "unit_id", "continuation"],
        "subject.",
      )
      if string_field(value, "continuation") != Some("resume_unit") {
        raise CheckpointFailed(InvalidField("subject.continuation"))
      }
      RunUnit(required_text(value, "run_id"), required_text(value, "unit_id"))
    }
    _ => raise CheckpointFailed(InvalidField("subject.kind"))
  }
}

///|
fn checkpoint_fields(with_identity : Bool) -> Array[String] {
  let fields = [
    "version", "checkpoint_id", "run_id", "run_definition_cid", "continuation_state_cid",
    "subject", "phase", "kind", "required_artifact", "review_projection_cid", "requirements",
    "reason_code", "human_summary", "created_at", "expires_at",
  ]
  if with_identity {
    fields.push("checkpoint_cid")
  }
  fields
}

///|
fn decode_checkpoint(
  value : @json.CanonicalValue,
  with_identity : Bool,
) -> (CheckpointRequest, String) raise CheckpointFailure {
  require_shape(value, checkpoint_fields(with_identity), "")
  if string_field(value, "version") != Some(CHECKPOINT_VERSION) {
    raise CheckpointFailed(InvalidField("version"))
  }
  let subject = decode_subject(required_object(value, "subject"))
  let phase = match parse_phase(required_text(value, "phase")) {
    Some(phase) => phase
    None => raise CheckpointFailed(InvalidField("phase"))
  }
  let kind = match parse_checkpoint_kind(required_text(value, "kind")) {
    Some(kind) => kind
    None => raise CheckpointFailed(InvalidField("kind"))
  }
  let artifact = required_object(value, "required_artifact")
  require_shape(
    artifact,
    ["artifact_type", "artifact_cid"],
    "required_artifact.",
  )
  if string_field(artifact, "artifact_type") !=
    Some(checkpoint_artifact_type(kind)) {
    raise CheckpointFailed(UnsupportedCombination)
  }
  let artifact_cid = required_text(artifact, "artifact_cid")
  let tokens = match string_list_field(value, "requirements") {
    Some(tokens) => tokens
    None => raise CheckpointFailed(InvalidField("requirements"))
  }
  let requirements : Array[CheckpointRequirement] = []
  for token in tokens {
    match parse_checkpoint_requirement(token) {
      Some(requirement) => requirements.push(requirement)
      None => raise CheckpointFailed(InvalidRequirements)
    }
  }
  let request : CheckpointRequest = {
    checkpoint_id: required_text(value, "checkpoint_id"),
    run_id: required_text(value, "run_id"),
    run_definition_cid: required_text(value, "run_definition_cid"),
    continuation_state_cid: required_text(value, "continuation_state_cid"),
    subject,
    phase,
    kind,
    required_artifact_cid: artifact_cid,
    review_projection_cid: required_text(value, "review_projection_cid"),
    requirements,
    reason_code: required_text(value, "reason_code"),
    human_summary: required_text(value, "human_summary"),
    created_at: required_text(value, "created_at"),
    expires_at: required_text(value, "expires_at"),
  }
  let identity = if with_identity {
    required_text(value, "checkpoint_cid")
  } else {
    ""
  }
  (request, identity)
}

///|
/// Admit a stored or received Checkpoint wire: closed shape, valid
/// combination and requirement list, and exact self CID.
pub fn admit_checkpoint_wire(
  wire : String,
  limits : WireLimits,
) -> Result[SealedCheckpoint, CheckpointIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let value = match parse_wire(wire, limits) {
    Some(value) => value
    None => return Err(InvalidWire)
  }
  let (request, claimed) = decode_checkpoint(value, true) catch {
    CheckpointFailed(issue) => return Err(issue)
  }
  if !valid_cid(claimed) {
    return Err(InvalidField("checkpoint_cid"))
  }
  let artifact = match seal_checkpoint(request, limits) {
    Ok(artifact) => artifact
    Err(issue) => return Err(issue)
  }
  if artifact.checkpoint_cid != claimed {
    return Err(IdentityMismatch)
  }
  Ok(artifact)
}

///|
/// Seal a Checkpoint body given in its wire form: every schema field except
/// `checkpoint_cid`, which the core computes.
pub fn seal_checkpoint_body(
  body_wire : String,
  limits : WireLimits,
) -> Result[SealedCheckpoint, CheckpointIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let value = match parse_wire(body_wire, limits) {
    Some(value) => value
    None => return Err(InvalidWire)
  }
  let (request, _) = decode_checkpoint(value, false) catch {
    CheckpointFailed(issue) => return Err(issue)
  }
  seal_checkpoint(request, limits)
}

///|
/// Typed persistence step. `stored_wire` must be the exact wire read back from
/// the committed store row for this Checkpoint.
pub fn confirm_checkpoint_persisted(
  artifact : SealedCheckpoint,
  stored_wire : String,
) -> Result[PersistedCheckpoint, CheckpointIssue] {
  if stored_wire != artifact.wire {
    return Err(PersistedWireMismatch)
  }
  Ok({ artifact, })
}

///|
/// A Checkpoint is expired at `now` once `now` reaches `expires_at`; a
/// Resolution decision must be strictly earlier than expiration.
pub fn checkpoint_expired_at(
  checkpoint : SealedCheckpoint,
  now : String,
) -> Result[Bool, CheckpointIssue] {
  if !valid_timestamp(now) {
    return Err(InvalidField("now"))
  }
  Ok(now >= checkpoint.checkpoint.expires_at)
}
