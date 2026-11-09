///|
/// Unsigned Resolution identity material owned by the existing Checkpoint
/// codec. This is not a persisted Checkpoint witness, Reviewer authentication,
/// approval, signing permission, grant or credential use claim.
struct PreparedResolutionProof {
  checkpoint : SealedCheckpoint
  body : @json.CanonicalValue
  actor : String
  decision : ResolutionDecision
  preimage : String
  limits : WireLimits
}

///|
/// Prepare the exact existing Resolution body without `proof` and
/// `resolution_cid`. No placeholder signature is inserted. Subject bindings,
/// decision/evidence framing and the decision window belong to this Owner;
/// current authorization and actual approval evidence admission remain separate.
pub fn prepare_resolution_proof(
  checkpoint : SealedCheckpoint,
  unsigned_wire : String,
  limits : WireLimits,
) -> Result[PreparedResolutionProof, ResolutionIssue] {
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  let value = match parse_wire(unsigned_wire, limits) {
    Some(value) => value
    None => return Err(ResolutionInvalidWire)
  }
  try {
    resolution_shape(
      value,
      [
        "version", "resolution_id", "checkpoint_id", "checkpoint_cid", "decision",
        "actor", "decided_at", "required_artifact_cid", "review_projection_cid",
      ],
      resolution_optional_fields(),
      "",
    )
    if string_field(value, "version") != Some(RESOLUTION_VERSION) {
      raise ResolutionFailed(ResolutionInvalidField("version"))
    }
    let (decision, _) = resolution_decision_evidence(value)
    ignore(text_of(value, "resolution_id", ""))
    let actor = text_of(value, "actor", "")
    let decided_at = time_field(value, "decided_at", "")
    check_resolution_subject(value, checkpoint)
    if decided_at < checkpoint.checkpoint.created_at ||
      decided_at >= checkpoint.checkpoint.expires_at {
      raise ResolutionFailed(DecisionOutsideWindow)
    }
    let preimage = match cid_of(value, limits) {
      Some(value) => value
      None => raise ResolutionFailed(ResolutionEncoding)
    }
    Ok({ checkpoint, body: value, actor, decision, preimage, limits, })
  } catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
/// The original nominal Checkpoint used for subject checks, not durable custody.
pub fn PreparedResolutionProof::checkpoint(
  self : PreparedResolutionProof,
) -> SealedCheckpoint {
  self.checkpoint
}

///|
/// The original body actor. The trusted current Reviewer must match it before
/// acquiring any signing use; this getter does not authenticate that actor.
pub fn PreparedResolutionProof::actor(self : PreparedResolutionProof) -> String {
  self.actor
}

///|
/// Original already-validated decision DATA. The Host must still recheck
/// cancellation/current eligibility and obtain independent authentication;
/// this getter grants no approval, signing use or continuation permission.
pub fn PreparedResolutionProof::decision(
  self : PreparedResolutionProof,
) -> ResolutionDecision {
  self.decision
}

///|
/// Existing unsigned Resolution CID text. No new identity domain is introduced.
pub fn PreparedResolutionProof::preimage(
  self : PreparedResolutionProof,
) -> String {
  self.preimage
}

///|
/// Attach externally supplied Ed25519 proof bytes and compute the existing
/// Resolution self CID. This only emits a candidate; signature verification,
/// Reviewer/Host authorization, evidence and commit remain with their Owners.
/// The preparation's original finite limits also bound this emission.
pub fn seal_prepared_resolution_proof(
  prepared : PreparedResolutionProof,
  key_id : String,
  signature : String,
) -> Result[String, ResolutionIssue] {
  let complete = match
    seal_prepared_reviewer_proof_body(
      prepared.body,
      key_id,
      signature,
      "resolution_cid",
      prepared.limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match wire_of(complete, prepared.limits) {
    Some(value) => Ok(value)
    None => Err(ResolutionEncoding)
  }
}

///|
// One closed proof encoding rule for the two existing Reviewer artifacts.
// Only this Owner's typed preparations call it, never arbitrary signing DATA.
fn seal_prepared_reviewer_proof_body(
  prepared : @json.CanonicalValue,
  key_id : String,
  signature : String,
  identity_field : String,
  limits : WireLimits,
) -> Result[@json.CanonicalValue, ResolutionIssue] {
  if key_id.is_empty() || key_id.length() > limits.max_wire_bytes {
    return Err(ResolutionInvalidField("proof.key_id"))
  }
  // Canonical base64 of exact Ed25519 64-byte output. Decode is bounded by the
  // fixed encoded length, not by an unbounded caller string or a secret body.
  if signature.length() != 88 || !valid_base64(signature) {
    return Err(ResolutionInvalidField("proof.signature"))
  }
  let bytes = @base64.decode(signature[:]) catch {
    _ => return Err(ResolutionInvalidField("proof.signature"))
  }
  if bytes.length() != 64 || @base64.encode(bytes) != signature {
    return Err(ResolutionInvalidField("proof.signature"))
  }
  let fields = match @json.object_fields(prepared) {
    Some(value) => value
    None => return Err(ResolutionEncoding)
  }
  let map : Map[String, Json] = Map([])
  for (name, value) in fields {
    map[name] = to_json(value)
  }
  map["proof"] = Json::object({
    "scheme": Json::string(PROOF_SCHEME),
    "key_id": Json::string(key_id),
    "signature": Json::string(signature),
  })
  let body = match canonical_of(Json::object(map), limits) {
    Some(value) => value
    None => return Err(ResolutionEncoding)
  }
  let cid = match cid_of(body, limits) {
    Some(value) => value
    None => return Err(ResolutionEncoding)
  }
  let complete = match
    @json.object_with_string_field(body, identity_field, cid) {
    Some(value) => value
    None => return Err(ResolutionEncoding)
  }
  Ok(complete)
}
