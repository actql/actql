///|
const RESOLUTION_VERSION : String = "actql-checkpoint-resolution/0.1"

///|
const VERIFIED_VERSION : String = "actql-verified-checkpoint-resolution/0.1"

///|
const EVIDENCE_VERSION : String = "actql-checkpoint-approval-evidence/0.1"

///|
const AUTHORIZATION_EVIDENCE_VERSION : String = "actql-checkpoint-resolution-authorization-evidence/0.1"

///|
const PROOF_SCHEME : String = "ed25519-v1"

///|
priv suberror ResolutionFailure {
  ResolutionFailed(ResolutionIssue)
}

///|
fn to_json(value : @json.CanonicalValue) -> Json {
  match value {
    Null => Json::null()
    Bool(flag) => Json::boolean(flag)
    Number(number) => Json::number(number)
    String(text) => Json::string(text)
    Array(items) => Json::array(@json.array_values(items).map(to_json))
    Object(fields) => {
      let map : Map[String, Json] = Map([])
      for field in @json.array_values(fields) {
        let (key, item) = field
        map[key] = to_json(item)
      }
      Json::object(map)
    }
  }
}

///|
fn resolution_shape(
  value : @json.CanonicalValue,
  required : Array[String],
  optional : Array[String],
  prefix : String,
) -> Unit raise ResolutionFailure {
  match closed_shape(value, required, optional) {
    Some(Unknown(key)) =>
      raise ResolutionFailed(ResolutionUnknownField(prefix + key))
    Some(Missing(key)) =>
      raise ResolutionFailed(ResolutionMissingField(prefix + key))
    Some(NotObject) => raise ResolutionFailed(ResolutionInvalidObject)
    None => ()
  }
}

///|
fn text_of(
  value : @json.CanonicalValue,
  key : String,
  prefix : String,
) -> String raise ResolutionFailure {
  match string_field(value, key) {
    Some(text) if text != "" => text
    _ => raise ResolutionFailed(ResolutionInvalidField(prefix + key))
  }
}

///|
fn cid_field(
  value : @json.CanonicalValue,
  key : String,
  prefix : String,
) -> String raise ResolutionFailure {
  let text = text_of(value, key, prefix)
  if !valid_cid(text) {
    raise ResolutionFailed(ResolutionInvalidField(prefix + key))
  }
  text
}

///|
fn time_field(
  value : @json.CanonicalValue,
  key : String,
  prefix : String,
) -> String raise ResolutionFailure {
  let text = text_of(value, key, prefix)
  if !valid_timestamp(text) {
    raise ResolutionFailed(ResolutionInvalidField(prefix + key))
  }
  text
}

///|
fn object_of(
  value : @json.CanonicalValue,
  key : String,
  prefix : String,
) -> @json.CanonicalValue raise ResolutionFailure {
  match @json.object_field(value, key) {
    Some(item) => item
    None => raise ResolutionFailed(ResolutionMissingField(prefix + key))
  }
}

///|
/// Returns the proof key ID after checking the closed proof shape.
fn proof_key(
  value : @json.CanonicalValue,
  key_field : String,
  prefix : String,
) -> String raise ResolutionFailure {
  resolution_shape(value, ["scheme", key_field, "signature"], [], prefix)
  if string_field(value, "scheme") != Some(PROOF_SCHEME) {
    raise ResolutionFailed(ResolutionInvalidField(prefix + "scheme"))
  }
  let signature = text_of(value, "signature", prefix)
  if !valid_base64(signature) {
    raise ResolutionFailed(ResolutionInvalidField(prefix + "signature"))
  }
  text_of(value, key_field, prefix)
}

///|
/// Verify a self CID: the CID over the envelope without its own CID field.
fn self_cid(
  value : @json.CanonicalValue,
  field : String,
  limits : WireLimits,
) -> Bool raise ResolutionFailure {
  let claimed = cid_field(value, field, "")
  let body = match @json.object_without_field(value, field) {
    Some(body) => body
    None => raise ResolutionFailed(ResolutionInvalidObject)
  }
  match cid_of(body, limits) {
    Some(cid) => cid == claimed
    None => raise ResolutionFailed(ResolutionEncoding)
  }
}

///|
/// Ed25519 signature preimage of a signed artifact: the UTF-8 text of the CID
/// of the artifact without both its self CID and its signature member. The
/// signed CID binds the artifact `version`, so a signature cannot be replayed
/// as another artifact kind.
fn unsigned_cid(
  value : @json.CanonicalValue,
  self_field : String,
  signature_field : String,
  limits : WireLimits,
) -> String raise ResolutionFailure {
  let without_self = match @json.object_without_field(value, self_field) {
    Some(body) => body
    None => raise ResolutionFailed(ResolutionInvalidObject)
  }
  let unsigned = match
    @json.object_without_field(without_self, signature_field) {
    Some(body) => body
    None => raise ResolutionFailed(ResolutionInvalidObject)
  }
  match cid_of(unsigned, limits) {
    Some(cid) => cid
    None => raise ResolutionFailed(ResolutionEncoding)
  }
}

///|
fn signature_preimage_of(
  wire : String,
  version : String,
  self_field : String,
  signature_field : String,
  limits : WireLimits,
) -> Result[String, ResolutionIssue] {
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  let value = match parse_wire(wire, limits) {
    Some(value) => value
    None => return Err(ResolutionInvalidWire)
  }
  if string_field(value, "version") != Some(version) {
    return Err(ResolutionInvalidField("version"))
  }
  for field in [self_field, signature_field] {
    if @json.object_field(value, field) is None {
      return Err(ResolutionMissingField(field))
    }
  }
  Ok(unsigned_cid(value, self_field, signature_field, limits)) catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
/// The text whose UTF-8 bytes `proof.signature` signs: the CID of the
/// `actql-checkpoint-resolution/0.1` without `resolution_cid` and `proof`.
/// The Host authorization port verifies the Ed25519 signature over it and
/// reports it as `HostAuthentication::proof_preimage`.
pub fn resolution_proof_preimage(
  resolution_wire : String,
  limits : WireLimits,
) -> Result[String, ResolutionIssue] {
  signature_preimage_of(
    resolution_wire,
    RESOLUTION_VERSION,
    "resolution_cid",
    "proof",
    limits,
  )
}

///|
/// The text whose UTF-8 bytes `host_attestation.signature` signs: the CID of
/// the `actql-verified-checkpoint-resolution/0.1` wrapper without
/// `verified_resolution_cid` and `host_attestation`.
pub fn verified_resolution_attestation_preimage(
  verified_wire : String,
  limits : WireLimits,
) -> Result[String, ResolutionIssue] {
  signature_preimage_of(
    verified_wire,
    VERIFIED_VERSION,
    "verified_resolution_cid",
    "host_attestation",
    limits,
  )
}

///|
fn resolution_fields() -> Array[String] {
  [
    "version", "resolution_id", "checkpoint_id", "checkpoint_cid", "decision", "actor",
    "decided_at", "required_artifact_cid", "review_projection_cid", "proof", "resolution_cid",
  ]
}

///|
/// A Resolution carries `run_id` and `run_definition_cid` for a Run-unit
/// Checkpoint, or only `prepare_attempt_id` for a preparation Checkpoint.
fn resolution_optional_fields() -> Array[String] {
  [
    "approval_evidence_cid", "run_id", "run_definition_cid", "prepare_attempt_id",
  ]
}

///|
fn subject_bindings(
  checkpoint : SealedCheckpoint,
) -> (Array[(String, String)], Array[String]) {
  match checkpoint.checkpoint.subject {
    RunUnit(run_id~, run_definition_cid~, ..) =>
      (
        [("run_id", run_id), ("run_definition_cid", run_definition_cid)],
        ["prepare_attempt_id"],
      )
    PrepareAttempt(prepare_attempt_id~) =>
      (
        [("prepare_attempt_id", prepare_attempt_id)],
        ["run_id", "run_definition_cid"],
      )
  }
}

///|
priv struct DecodedResolution {
  value : @json.CanonicalValue
  resolution_id : String
  resolution_cid : String
  decision : ResolutionDecision
  actor : String
  decided_at : String
  key_id : String
  approval_evidence_cid : String?
  proof_preimage : String
}

///|
fn decode_resolution(
  value : @json.CanonicalValue,
  checkpoint : SealedCheckpoint,
  limits : WireLimits,
) -> DecodedResolution raise ResolutionFailure {
  resolution_shape(value, resolution_fields(), resolution_optional_fields(), "")
  if string_field(value, "version") != Some(RESOLUTION_VERSION) {
    raise ResolutionFailed(ResolutionInvalidField("version"))
  }
  let decision = match string_field(value, "decision") {
    Some("approved") => Approved
    Some("rejected") => Rejected
    _ => raise ResolutionFailed(ResolutionInvalidField("decision"))
  }
  let evidence_cid = match @json.object_field(value, "approval_evidence_cid") {
    None => None
    Some(_) => Some(cid_field(value, "approval_evidence_cid", ""))
  }
  match (decision, evidence_cid) {
    (Approved, None) => raise ResolutionFailed(EvidenceRequired)
    (Rejected, Some(_)) => raise ResolutionFailed(EvidenceForbidden)
    _ => ()
  }
  let resolution_id = text_of(value, "resolution_id", "")
  let actor = text_of(value, "actor", "")
  let decided_at = time_field(value, "decided_at", "")
  let key_id = proof_key(object_of(value, "proof", ""), "key_id", "proof.")
  let (identity, forbidden) = subject_bindings(checkpoint)
  for field in forbidden {
    if @json.object_field(value, field) is Some(_) {
      raise ResolutionFailed(CheckpointBindingMismatch(field))
    }
  }
  for binding in identity {
    let (field, _) = binding
    if @json.object_field(value, field) is None {
      raise ResolutionFailed(ResolutionMissingField(field))
    }
  }
  let bindings = [
    ("checkpoint_id", checkpoint.checkpoint.checkpoint_id),
    ("checkpoint_cid", checkpoint.checkpoint_cid),
    ("required_artifact_cid", checkpoint.checkpoint.required_artifact_cid),
    ("review_projection_cid", checkpoint.checkpoint.review_projection_cid),
  ]
  bindings.push_iter(identity.iter())
  for binding in bindings {
    let (field, expected) = binding
    if field.has_suffix("_cid") {
      ignore(cid_field(value, field, ""))
    }
    if text_of(value, field, "") != expected {
      raise ResolutionFailed(CheckpointBindingMismatch(field))
    }
  }
  if !self_cid(value, "resolution_cid", limits) {
    raise ResolutionFailed(ResolutionIdentityMismatch)
  }
  {
    value,
    resolution_id,
    resolution_cid: text_of(value, "resolution_cid", ""),
    decision,
    actor,
    decided_at,
    key_id,
    approval_evidence_cid: evidence_cid,
    proof_preimage: unsigned_cid(value, "resolution_cid", "proof", limits),
  }
}

///|
fn evidence_fields() -> Array[String] {
  [
    "version", "kind", "checkpoint_cid", "review_projection_cid", "compatibility_approval",
  ]
}

///|
fn run_scope_approval_fields() -> Array[String] {
  [
    "version", "prepared_invocation_cid", "review_projection_cid", "claim", "approver",
    "approved_at", "expires_at", "proof", "run_scope_approval_cid",
  ]
}

///|
fn attestation_fields() -> Array[String] {
  [
    "version", "effect_preview_cid", "review_projection_cid", "approver", "approved_at",
    "authority_scope_cid", "claims", "proof", "attestation_cid",
  ]
}

///|
/// Approved Resolution Evidence: closed shape, exact hash, and bindings to the
/// same Checkpoint, review projection, required artifact, reviewer, and every
/// requirement claim carried by the Checkpoint.
fn check_evidence(
  wire : String,
  expected_cid : String,
  checkpoint : SealedCheckpoint,
  actor : String,
  expected_authority_scope_cid : String,
  limits : WireLimits,
  model_binding : ModelCheckpointBinding?,
) -> @json.CanonicalValue raise ResolutionFailure {
  let value = match parse_wire(wire, limits) {
    Some(value) => value
    None => raise ResolutionFailed(ResolutionInvalidWire)
  }
  match cid_of(value, limits) {
    Some(cid) if cid == expected_cid => ()
    Some(_) => raise ResolutionFailed(EvidenceMismatch("approval_evidence_cid"))
    None => raise ResolutionFailed(ResolutionEncoding)
  }
  let prefix = "approval_evidence."
  resolution_shape(value, evidence_fields(), [], prefix)
  if string_field(value, "version") != Some(EVIDENCE_VERSION) {
    raise ResolutionFailed(ResolutionInvalidField(prefix + "version"))
  }
  let request = checkpoint.checkpoint
  if string_field(value, "kind") != Some(checkpoint_kind_token(request.kind)) {
    raise ResolutionFailed(EvidenceMismatch("kind"))
  }
  if cid_field(value, "checkpoint_cid", prefix) != checkpoint.checkpoint_cid {
    raise ResolutionFailed(EvidenceMismatch("checkpoint_cid"))
  }
  if cid_field(value, "review_projection_cid", prefix) !=
    request.review_projection_cid {
    raise ResolutionFailed(EvidenceMismatch("review_projection_cid"))
  }
  let approval = object_of(value, "compatibility_approval", prefix)
  let nested = prefix + "compatibility_approval."
  match request.kind {
    EffectSet => {
      resolution_shape(approval, attestation_fields(), [], nested)
      if string_field(approval, "version") !=
        Some("actql-approval-attestation/0.1") {
        raise ResolutionFailed(ResolutionInvalidField(nested + "version"))
      }
      if cid_field(approval, "effect_preview_cid", nested) !=
        request.required_artifact_cid {
        raise ResolutionFailed(EvidenceMismatch("effect_preview_cid"))
      }
      if cid_field(approval, "authority_scope_cid", nested) !=
        expected_authority_scope_cid {
        raise ResolutionFailed(EvidenceMismatch("authority_scope_cid"))
      }
      let claims = match string_list_field(approval, "claims") {
        Some(claims) => claims
        None =>
          raise ResolutionFailed(ResolutionInvalidField(nested + "claims"))
      }
      if claims != ["effect_scope_approved"] &&
        claims != ["effect_scope_approved", "partial_application_accepted"] {
        raise ResolutionFailed(ResolutionInvalidField(nested + "claims"))
      }
      for requirement in request.requirements {
        if !claims.contains(checkpoint_requirement_token(requirement)) {
          raise ResolutionFailed(EvidenceMismatch("claims"))
        }
      }
      if !self_cid(approval, "attestation_cid", limits) {
        raise ResolutionFailed(EvidenceMismatch("attestation_cid"))
      }
    }
    _ => {
      resolution_shape(approval, run_scope_approval_fields(), [], nested)
      if string_field(approval, "version") !=
        Some("actql-run-scope-approval/0.1") {
        raise ResolutionFailed(ResolutionInvalidField(nested + "version"))
      }
      if string_field(approval, "claim") != Some("invocation_scope_approved") {
        raise ResolutionFailed(ResolutionInvalidField(nested + "claim"))
      }
      let prepared = cid_field(approval, "prepared_invocation_cid", nested)
      if request.kind == ModelInvocation {
        guard model_binding is Some(binding) &&
          binding.checkpoint.checkpoint_cid == checkpoint.checkpoint_cid else {
          raise ResolutionFailed(EvidenceMismatch("model_checkpoint_binding"))
        }
        if prepared !=
          @publication.model_invocation_scope_prepared_cid(binding.scope) {
          raise ResolutionFailed(EvidenceMismatch("prepared_invocation_cid"))
        }
      }
      if request.kind == RunScope && prepared != request.required_artifact_cid {
        raise ResolutionFailed(EvidenceMismatch("prepared_invocation_cid"))
      }
      let expires = time_field(approval, "expires_at", nested)
      if expires <= time_field(approval, "approved_at", nested) {
        raise ResolutionFailed(EvidenceMismatch("expires_at"))
      }
      if !self_cid(approval, "run_scope_approval_cid", limits) {
        raise ResolutionFailed(EvidenceMismatch("run_scope_approval_cid"))
      }
    }
  }
  if cid_field(approval, "review_projection_cid", nested) !=
    request.review_projection_cid {
    raise ResolutionFailed(EvidenceMismatch("review_projection_cid"))
  }
  if text_of(approval, "approver", nested) != actor {
    raise ResolutionFailed(EvidenceMismatch("approver"))
  }
  ignore(time_field(approval, "approved_at", nested))
  ignore(
    proof_key(object_of(approval, "proof", nested), "key_id", nested + "proof."),
  )
  value
}

///|
/// Host-internal dedupe identity of the unique resume intent, derived from the
/// Checkpoint and Resolution CIDs.
pub fn resume_intent_id(
  checkpoint_cid : String,
  resolution_cid : String,
  limits : WireLimits,
) -> String? {
  if !valid_cid(checkpoint_cid) || !valid_cid(resolution_cid) {
    return None
  }
  let value = canonical_of(
    Json::object({
      "checkpoint_cid": Json::string(checkpoint_cid),
      "resolution_cid": Json::string(resolution_cid),
    }),
    limits,
  )
  match value {
    Some(value) => cid_of(value, limits)
    None => None
  }
}

///|
fn admit_resolution_body(
  checkpoint : SealedCheckpoint,
  resolution_wire : String,
  approval_evidence_wire : String?,
  authentication : HostAuthentication,
  authorities : Array[ReviewerAuthority],
  verified_at : String,
  limits : WireLimits,
  model_binding : ModelCheckpointBinding?,
) -> AdmittedResolution raise ResolutionFailure {
  if !valid_limits(limits) {
    raise ResolutionFailed(ResolutionInvalidLimits)
  }
  if !valid_timestamp(verified_at) {
    raise ResolutionFailed(ResolutionInvalidField("verified_at"))
  }
  let value = match parse_wire(resolution_wire, limits) {
    Some(value) => value
    None => raise ResolutionFailed(ResolutionInvalidWire)
  }
  let resolution = decode_resolution(value, checkpoint, limits)
  let request = checkpoint.checkpoint
  if resolution.decided_at < request.created_at ||
    resolution.decided_at >= request.expires_at {
    raise ResolutionFailed(DecisionOutsideWindow)
  }
  if resolution.decided_at > verified_at {
    raise ResolutionFailed(DecisionAfterVerification)
  }
  if authentication.proof_preimage != resolution.proof_preimage {
    raise ResolutionFailed(AuthenticationMismatch("proof_preimage"))
  }
  if authentication.key_id != resolution.key_id {
    raise ResolutionFailed(AuthenticationMismatch("key_id"))
  }
  if authentication.reviewer_id != resolution.actor {
    raise ResolutionFailed(AuthenticationMismatch("reviewer_id"))
  }
  if !valid_cid(authentication.authority_context_cid) {
    raise ResolutionFailed(AuthenticationMismatch("authority_context_cid"))
  }
  if !valid_cid(authentication.expected_authority_scope_cid) {
    raise ResolutionFailed(
      AuthenticationMismatch("expected_authority_scope_cid"),
    )
  }
  if !valid_cid(authentication.policy_cid) {
    raise ResolutionFailed(AuthenticationMismatch("policy_cid"))
  }
  let permitted = authorities.any(authority => {
    authority.key_id == authentication.key_id &&
    authority.reviewer_id == authentication.reviewer_id
  })
  if !permitted {
    raise ResolutionFailed(AuthorityNotPermitted)
  }
  let evidence = match
    (resolution.approval_evidence_cid, approval_evidence_wire) {
    (Some(cid), Some(wire)) =>
      Some(
        check_evidence(
          wire,
          cid,
          checkpoint,
          resolution.actor,
          authentication.expected_authority_scope_cid,
          limits,
          model_binding,
        ),
      )
    (Some(_), None) => raise ResolutionFailed(EvidenceRequired)
    (None, Some(_)) => raise ResolutionFailed(EvidenceForbidden)
    (None, None) => None
  }
  let authorization_evidence = Json::object({
    "version": Json::string(AUTHORIZATION_EVIDENCE_VERSION),
    "resolution_cid": Json::string(resolution.resolution_cid),
    "checkpoint_cid": Json::string(checkpoint.checkpoint_cid),
    "authority_context_cid": Json::string(authentication.authority_context_cid),
    "key_id": Json::string(authentication.key_id),
  })
  let authorization_cid = match canonical_of(authorization_evidence, limits) {
    Some(canonical) =>
      match cid_of(canonical, limits) {
        Some(cid) => cid
        None => raise ResolutionFailed(ResolutionEncoding)
      }
    None => raise ResolutionFailed(ResolutionEncoding)
  }
  let fields : Map[String, Json] = {
    "version": Json::string(VERIFIED_VERSION),
    "resolution": to_json(resolution.value),
    "authorization_evidence": authorization_evidence,
    "authorization_evidence_cid": Json::string(authorization_cid),
    "verified_by_policy_cid": Json::string(authentication.policy_cid),
    "verified_reviewer_id": Json::string(authentication.reviewer_id),
    "authorization_context_cid": Json::string(
      authentication.authority_context_cid,
    ),
    "requirements": string_array_json(
      request.requirements.map(checkpoint_requirement_token),
    ),
    "verified_at": Json::string(verified_at),
  }
  if evidence is Some(item) {
    fields["approval_evidence"] = to_json(item)
  }
  let body = match canonical_of(Json::object(fields), limits) {
    Some(body) => body
    None => raise ResolutionFailed(ResolutionEncoding)
  }
  // The wrapper without `host_attestation` and `verified_resolution_cid` is
  // exactly this body, so its CID text is the attestation preimage.
  let preimage = match cid_of(body, limits) {
    Some(cid) => cid
    None => raise ResolutionFailed(ResolutionEncoding)
  }
  {
    checkpoint_cid: checkpoint.checkpoint_cid,
    resolution_id: resolution.resolution_id,
    resolution_cid: resolution.resolution_cid,
    decision: resolution.decision,
    attestation_preimage: preimage,
    body,
  }
}

///|
/// Admit one `actql-checkpoint-resolution/0.1` for the exact sealed
/// Checkpoint after the Host authorization port authenticated it.
///
/// `authentication` is the Host port's verified result; `authorities` is the
/// reviewer authority set the Host bound to this Checkpoint. The returned
/// `attestation_preimage` is the unsigned verified-wrapper CID text (the CID
/// of the wrapper without `host_attestation` and `verified_resolution_cid`);
/// the Host signs its UTF-8 bytes and calls `seal_verified_resolution`.
pub fn admit_checkpoint_resolution(
  checkpoint : SealedCheckpoint,
  resolution_wire : String,
  approval_evidence_wire : String?,
  authentication : HostAuthentication,
  authorities : Array[ReviewerAuthority],
  verified_at : String,
  limits : WireLimits,
  model_binding? : ModelCheckpointBinding,
) -> Result[AdmittedResolution, ResolutionIssue] {
  Ok(
    admit_resolution_body(
      checkpoint, resolution_wire, approval_evidence_wire, authentication, authorities,
      verified_at, limits, model_binding,
    ),
  ) catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
priv struct AttestedWrapper {
  verified_resolution_cid : String
  verified_at : String
  wire : String
}

///|
fn attach_attestation(
  admitted : AdmittedResolution,
  host_key_id : String,
  signature : String,
  limits : WireLimits,
) -> Result[AttestedWrapper, ResolutionIssue] {
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  if host_key_id.is_empty() || !valid_base64(signature) {
    return Err(InvalidAttestation)
  }
  let fields = match @json.object_fields(admitted.body) {
    Some(fields) => fields
    None => return Err(ResolutionEncoding)
  }
  let map : Map[String, Json] = Map([])
  for field in fields {
    let (key, item) = field
    map[key] = to_json(item)
  }
  map["host_attestation"] = Json::object({
    "scheme": Json::string(PROOF_SCHEME),
    "host_key_id": Json::string(host_key_id),
    "signature": Json::string(signature),
  })
  let body = match canonical_of(Json::object(map), limits) {
    Some(body) => body
    None => return Err(ResolutionEncoding)
  }
  let cid = match cid_of(body, limits) {
    Some(cid) => cid
    None => return Err(ResolutionEncoding)
  }
  let complete = match
    @json.object_with_string_field(body, "verified_resolution_cid", cid) {
    Some(value) => value
    None => return Err(ResolutionEncoding)
  }
  let wire = match wire_of(complete, limits) {
    Some(wire) => wire
    None => return Err(ResolutionEncoding)
  }
  let verified_at = match string_field(admitted.body, "verified_at") {
    Some(text) => text
    None => return Err(ResolutionEncoding)
  }
  Ok({ verified_resolution_cid: cid, verified_at, wire, })
}

///|
/// Attach the Host attestation and compute the verified wrapper self CID.
pub fn seal_verified_resolution(
  admitted : AdmittedResolution,
  host_key_id : String,
  signature : String,
  limits : WireLimits,
) -> Result[VerifiedResolution, ResolutionIssue] {
  let attested = match
    attach_attestation(admitted, host_key_id, signature, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let intent = match admitted.decision {
    Approved =>
      match
        resume_intent_id(
          admitted.checkpoint_cid,
          admitted.resolution_cid,
          limits,
        ) {
        Some(id) => Some(id)
        None => return Err(ResolutionEncoding)
      }
    Rejected => None
  }
  Ok({
    checkpoint_cid: admitted.checkpoint_cid,
    resolution_id: admitted.resolution_id,
    resolution_cid: admitted.resolution_cid,
    decision: admitted.decision,
    verified_resolution_cid: attested.verified_resolution_cid,
    verified_at: attested.verified_at,
    wire: attested.wire,
    resume_intent_id: intent,
  })
}

///|
/// Admit an immediate delegated permit or reject. `checkpoint` is the exact
/// `actql-execution-checkpoint/0.1` body the Host would persist if it
/// deferred; its `checkpoint_cid` is the decision subject CID. The Resolution
/// is validated exactly like a deferred one (subject and preparation or Run
/// identity, required artifact, review projection, decision window, approval
/// Evidence, proof preimage and reviewer authority), but nothing here seals a
/// persistable Checkpoint: the result cannot be committed, projected as
/// waiting, or turned into a resume intent.
pub fn admit_immediate_resolution(
  checkpoint : CheckpointRequest,
  resolution_wire : String,
  approval_evidence_wire : String?,
  authentication : HostAuthentication,
  authorities : Array[ReviewerAuthority],
  verified_at : String,
  limits : WireLimits,
  model_binding? : ModelCheckpointBinding,
) -> Result[ImmediateAdmittedResolution, ResolutionIssue] {
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  let subject = match seal_checkpoint(checkpoint, limits) {
    Ok(subject) => subject
    Err(_) => return Err(ResolutionInvalidField("checkpoint"))
  }
  match
    admit_checkpoint_resolution(
      subject,
      resolution_wire,
      approval_evidence_wire,
      authentication,
      authorities,
      verified_at,
      limits,
      model_binding?,
    ) {
    Ok(admitted) => Ok({ admitted, })
    Err(issue) => Err(issue)
  }
}

///|
/// Decision subject CID: the `checkpoint_cid` of the body the Host did not
/// persist.
pub fn ImmediateAdmittedResolution::checkpoint_cid(
  self : ImmediateAdmittedResolution,
) -> String {
  self.admitted.checkpoint_cid
}

///|
pub fn ImmediateAdmittedResolution::resolution_cid(
  self : ImmediateAdmittedResolution,
) -> String {
  self.admitted.resolution_cid
}

///|
pub fn ImmediateAdmittedResolution::decision(
  self : ImmediateAdmittedResolution,
) -> ResolutionDecision {
  self.admitted.decision
}

///|
/// Unsigned verified-wrapper CID text the Host attests.
pub fn ImmediateAdmittedResolution::attestation_preimage(
  self : ImmediateAdmittedResolution,
) -> String {
  self.admitted.attestation_preimage
}

///|
/// Attach the Host attestation to an immediate answer. The result is decision
/// evidence only; it has no resume intent.
pub fn seal_immediate_resolution(
  admitted : ImmediateAdmittedResolution,
  host_key_id : String,
  signature : String,
  limits : WireLimits,
) -> Result[ImmediateResolution, ResolutionIssue] {
  let inner = admitted.admitted
  match attach_attestation(inner, host_key_id, signature, limits) {
    Ok(attested) =>
      Ok({
        checkpoint_cid: inner.checkpoint_cid,
        resolution_id: inner.resolution_id,
        resolution_cid: inner.resolution_cid,
        decision: inner.decision,
        verified_resolution_cid: attested.verified_resolution_cid,
        verified_at: attested.verified_at,
        wire: attested.wire,
      })
    Err(issue) => Err(issue)
  }
}

///|
/// Read the permission of one committed approved verified Resolution wrapper
/// (`actql-verified-checkpoint-resolution/0.1`) for a resumed dispatch. The
/// claims are exactly those the stored approval evidence establishes, never
/// the claims a Host asks for: a run-scope style approval establishes its one
/// `claim`, an Effect Set attestation its `claims`.
pub fn resumed_approval(
  verified_wire : String,
  limits : WireLimits,
) -> Result[ResumedApproval, ResolutionIssue] {
  Ok(resumed_approval_body(verified_wire, limits)) catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
fn resumed_approval_body(
  verified_wire : String,
  limits : WireLimits,
) -> ResumedApproval raise ResolutionFailure {
  if !valid_limits(limits) {
    raise ResolutionFailed(ResolutionInvalidLimits)
  }
  let value = match parse_wire(verified_wire, limits) {
    Some(value) => value
    None => raise ResolutionFailed(ResolutionInvalidWire)
  }
  if string_field(value, "version") != Some(VERIFIED_VERSION) {
    raise ResolutionFailed(ResolutionInvalidField("version"))
  }
  if !self_cid(value, "verified_resolution_cid", limits) {
    raise ResolutionFailed(ResolutionIdentityMismatch)
  }
  let resolution = object_of(value, "resolution", "")
  if string_field(resolution, "decision") != Some("approved") {
    raise ResolutionFailed(ResolutionInvalidField("resolution.decision"))
  }
  let evidence = match @json.object_field(value, "approval_evidence") {
    Some(item) => item
    None => raise ResolutionFailed(EvidenceRequired)
  }
  let prefix = "approval_evidence.compatibility_approval."
  let approval = object_of(
    evidence, "compatibility_approval", "approval_evidence.",
  )
  guard string_field(evidence, "kind") is Some(kind_token) &&
    parse_checkpoint_kind(kind_token) is Some(kind) else {
    raise ResolutionFailed(EvidenceMismatch("kind"))
  }
  let effect = kind == EffectSet
  let (claims, expires_at) = if effect {
    match string_list_field(approval, "claims") {
      Some(claims) => (claims, None)
      None => raise ResolutionFailed(ResolutionInvalidField(prefix + "claims"))
    }
  } else {
    (
      [text_of(approval, "claim", prefix)],
      Some(time_field(approval, "expires_at", prefix)),
    )
  }
  {
    checkpoint_cid: cid_field(resolution, "checkpoint_cid", "resolution."),
    resolution_cid: cid_field(resolution, "resolution_cid", "resolution."),
    verified_resolution_cid: cid_field(value, "verified_resolution_cid", ""),
    reviewer_id: text_of(value, "verified_reviewer_id", ""),
    claims,
    expires_at,
  }
}

///|
/// Whether the approval still authorizes new work at the Host-trusted time
/// `at`: strictly before its `expires_at`. This is the lifetime of the granted
/// permission, independent of the Checkpoint answer deadline and of any
/// resume lease. An invalid time never authorizes.
pub fn resumed_approval_current(
  approval : ResumedApproval,
  at : String,
) -> Bool {
  if !valid_timestamp(at) {
    return false
  }
  match approval.expires_at {
    Some(expires) => at < expires
    None => true
  }
}
