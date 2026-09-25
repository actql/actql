///|
/// Canonical 0.1 risk-acceptance body. Admission establishes its identity and
/// semantic bindings, not the issuer's signature or current authority.
pub struct EffectRiskAcceptanceBody {
  cid : String
  unsigned_payload_cid : String
  issuer_kind : String
  decision : String
  issuer_evidence_cid : String
  policy_cid : String
  effect_preview_cid : String
  review_projection_cid : String
  authority_scope_cid : String
  validity_evidence_cid : String
  authentication_evidence_cid : String
  scope_approved : Bool
  partial_application_accepted : Bool
}

///|
pub(all) enum EffectRiskAcceptanceIssue {
  InvalidLimits
  InvalidWire
  InvalidShape
  InvalidIdentity
  Encoding
  ForeignPreview
  ForeignReviewProjection
  ForeignAuthority
  ForeignPolicy
  ForeignValidity
  ForeignIssuer
  ForeignIssuerKind
  ForeignDecision
  ForeignAuthentication
  MissingScopeAcceptance
  MissingPartialAcceptance
} derive(Debug)

///|
fn risk_text(value : @json.CanonicalValue, field : String) -> String? {
  match @json.object_field(value, field) {
    Some(@json.String(text)) => Some(text)
    _ => None
  }
}

///|
fn risk_cid(value : @json.CanonicalValue, field : String) -> String? {
  match risk_text(value, field) {
    Some(text) if effect_cid_valid(text) => Some(text)
    _ => None
  }
}

///|
/// Validate the complete transported body without treating a CID, signature
/// reference, or issuer label as proof of authentication.
pub fn admit_effect_risk_acceptance_body(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectRiskAcceptanceBody, EffectRiskAcceptanceIssue] {
  if max_wire_bytes < 1 ||
    max_wire_bytes > 1000000 ||
    max_nodes < 12 ||
    max_nodes > 1000 ||
    max_depth < 1 ||
    max_depth > 32 {
    return Err(InvalidLimits)
  }
  let parsed = match
    @source.parse_json(wire, {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidWire)
  }
  let value = @json.from_source(parsed, max_nodes, max_depth, max_wire_bytes) catch {
    _ => return Err(InvalidWire)
  }
  let canonical = @json.stringify_value(
    value, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidWire)
  }
  guard @json.object_fields(value) is Some(fields) &&
    fields.length() == 12 &&
    risk_text(value, "version") == Some("actql-effect-risk-acceptance/0.1") &&
    risk_text(value, "issuer_kind") is Some(issuer_kind) &&
    (issuer_kind == "human" || issuer_kind == "policy") &&
    risk_text(value, "decision") is Some(decision) &&
    (decision == "allow" || decision == "approved") &&
    risk_cid(value, "issuer_evidence_cid") is Some(issuer_evidence_cid) &&
    risk_cid(value, "policy_cid") is Some(policy_cid) &&
    risk_cid(value, "effect_preview_cid") is Some(effect_preview_cid) &&
    risk_cid(value, "review_projection_cid") is Some(review_projection_cid) &&
    risk_cid(value, "authority_scope_cid") is Some(authority_scope_cid) &&
    risk_cid(value, "validity_evidence_cid") is Some(validity_evidence_cid) &&
    risk_cid(value, "authentication_evidence_cid")
    is Some(authentication_evidence_cid) &&
    risk_cid(value, "self_cid") is Some(cid) &&
    @json.object_field(value, "claims") is Some(@json.Array(claims_frozen)) else {
    return Err(InvalidShape)
  }
  let claims = @json.array_values(claims_frozen)
  if claims.is_empty() || claims.length() > 2 {
    return Err(InvalidShape)
  }
  let mut scope_approved = false
  let mut partial_application_accepted = false
  for claim in claims {
    match claim {
      @json.String("effect_scope_approved") if !scope_approved =>
        scope_approved = true
      @json.String("partial_application_accepted") if !partial_application_accepted =>
        partial_application_accepted = true
      _ => return Err(InvalidShape)
    }
  }
  guard @json.object_without_field(value, "self_cid") is Some(body) else {
    return Err(InvalidShape)
  }
  let expected = @json.cid_value(body, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if expected != cid {
    return Err(InvalidIdentity)
  }
  guard @json.object_without_field(body, "authentication_evidence_cid")
    is Some(unsigned_body) else {
    return Err(InvalidShape)
  }
  let unsigned_payload_cid = @json.cid_value(
    unsigned_body, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  Ok({
    cid,
    unsigned_payload_cid,
    issuer_kind,
    decision,
    issuer_evidence_cid,
    policy_cid,
    effect_preview_cid,
    review_projection_cid,
    authority_scope_cid,
    validity_evidence_cid,
    authentication_evidence_cid,
    scope_approved,
    partial_application_accepted,
  })
}

///|
/// Detached authentication signs this CID, excluding self_cid and the
/// authentication reference. It is not proof that any issuer is trusted.
pub fn effect_risk_acceptance_unsigned_payload_cid(
  body : EffectRiskAcceptanceBody,
) -> String {
  body.unsigned_payload_cid
}

///|
/// Compare an admitted body with exact Host-verified facts for this Preview.
/// The Host must authenticate the issuer and evidence, check policy, expiry,
/// and current authority before passing those facts. This is not an apply
/// permit and must never be the sole gate before a physical mutation.
///
/// `require_partial_application` is the Host's declared policy for the
/// delegated decision that produced this body. Effect Set member count alone
/// never requires `partial_application_accepted`; when the Host policy
/// declares it, a body without the claim is not an accepted delegation.
pub fn check_effect_risk_acceptance_body(
  preview : @publication.EffectPreviewIdentity,
  body : EffectRiskAcceptanceBody,
  review_projection_cid : String,
  authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  require_partial_application : Bool,
) -> Result[Unit, EffectRiskAcceptanceIssue] {
  if body.effect_preview_cid !=
    @publication.effect_preview_semantic_identity(preview) {
    return Err(ForeignPreview)
  }
  if body.review_projection_cid != review_projection_cid {
    return Err(ForeignReviewProjection)
  }
  if body.authority_scope_cid != authority_scope_cid {
    return Err(ForeignAuthority)
  }
  if body.policy_cid != policy_cid {
    return Err(ForeignPolicy)
  }
  if body.validity_evidence_cid != validity_evidence_cid {
    return Err(ForeignValidity)
  }
  if body.issuer_evidence_cid != issuer_evidence_cid {
    return Err(ForeignIssuer)
  }
  if body.issuer_kind != issuer_kind {
    return Err(ForeignIssuerKind)
  }
  if body.decision != decision {
    return Err(ForeignDecision)
  }
  if body.authentication_evidence_cid != authentication_evidence_cid {
    return Err(ForeignAuthentication)
  }
  if !body.scope_approved {
    return Err(MissingScopeAcceptance)
  }
  if require_partial_application && !body.partial_application_accepted {
    return Err(MissingPartialAcceptance)
  }
  Ok(())
}
