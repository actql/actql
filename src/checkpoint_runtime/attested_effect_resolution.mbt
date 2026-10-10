///|
/// An existing Owner reconstruction, not a verified physical signature or an
/// execution permit. The Native caller verifies this exact attestation preimage
/// using independently installed Host keys before using the Resolution.
pub struct AttestedEffectResolution {
  resolution : VerifiedResolution
  host_key_id : String
  signature : String
  attestation_preimage : String
}

///|
/// Re-admit the signed wrapper against the original Effect Checkpoint and the
/// current independently trusted reviewer authentication. Re-sealing through
/// the existing Owner checks every wrapper fact, evidence and self identity.
/// No storage, claim, current authority lookup or physical execution occurs.
pub fn admit_attested_effect_resolution(
  checkpoint : SealedCheckpoint,
  verified_wire : String,
  authentication : HostAuthentication,
  authorities : Array[ReviewerAuthority],
  limits : WireLimits,
) -> Result[AttestedEffectResolution, ResolutionIssue] {
  Ok(
    admit_attested_effect_resolution_body(
      checkpoint, verified_wire, authentication, authorities, limits,
    ),
  ) catch {
    ResolutionFailed(issue) => Err(issue)
  }
}

///|
fn admit_attested_effect_resolution_body(
  checkpoint : SealedCheckpoint,
  verified_wire : String,
  authentication : HostAuthentication,
  authorities : Array[ReviewerAuthority],
  limits : WireLimits,
) -> AttestedEffectResolution raise ResolutionFailure {
  if !valid_limits(limits) {
    raise ResolutionFailed(ResolutionInvalidLimits)
  }
  if checkpoint.checkpoint.kind != EffectSet {
    raise ResolutionFailed(ResolutionInvalidField("kind"))
  }
  let value = match parse_wire(verified_wire, limits) {
    Some(value) => value
    None => raise ResolutionFailed(ResolutionInvalidWire)
  }
  let resolution = object_of(value, "resolution", "")
  let resolution_wire = match wire_of(resolution, limits) {
    Some(value) => value
    None => raise ResolutionFailed(ResolutionEncoding)
  }
  let evidence_wire = match @json.object_field(value, "approval_evidence") {
    Some(value) =>
      match wire_of(value, limits) {
        Some(value) => Some(value)
        None => raise ResolutionFailed(ResolutionEncoding)
      }
    None => None
  }
  let verified_at = time_field(value, "verified_at", "")
  let admitted = admit_resolution_body(
    checkpoint,
    resolution_wire,
    evidence_wire,
    authentication,
    authorities,
    verified_at,
    limits,
    None,
  )
  let attestation = object_of(value, "host_attestation", "")
  let host_key_id = text_of(attestation, "host_key_id", "host_attestation.")
  let signature = text_of(attestation, "signature", "host_attestation.")
  let verified = match
    seal_verified_resolution(admitted, host_key_id, signature, limits) {
    Ok(value) => value
    Err(issue) => raise ResolutionFailed(issue)
  }
  if wire_of(value, limits) != Some(verified.wire) {
    raise ResolutionFailed(ResolutionIdentityMismatch)
  }
  {
    resolution: verified,
    host_key_id,
    signature,
    attestation_preimage: admitted.attestation_preimage,
  }
}
