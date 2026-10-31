///|
/// Selected by the trusted original Host context, never by a signer, a Source
/// grant or an incoming Resume envelope. One signer may serve many principals.
pub(all) struct NativeEffectReviewerSelection {
  principal_id : String
  checkpoint_cid : String
} derive(Eq, Debug)

///|
/// A snapshot of the existing current Reviewer registration. The installation
/// must authorize the selected original principal for this exact Checkpoint.
/// These fields are not imported from the submitted Resolution.
pub(all) struct NativeEffectReviewerRegistration {
  selection : NativeEffectReviewerSelection
  key_id : String
  reviewer_id : String
  public_key_pem : String
  approval_authority_scope_cid : String
  authority_context_cid : String
  policy_cid : String
} derive(Eq, Debug)

///|
/// Physical signature and current registration ports installed independently
/// by the Host. This owns no approval registry, Resume claim or cleanup state.
pub(all) struct NativeEffectReviewerInstallation {
  crypto : @signature.Library
  current_site : () -> Bool
  read_current : (NativeEffectReviewerSelection, String) -> NativeEffectReviewerRegistration?
}

///|
priv struct NativeReviewerProof {
  key_id : String
  reviewer_id : String
  signature_url : String
  preimage : String
}

///|
fn native_reviewer_identifier(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  value
  .iter()
  .all(character => {
    let code = character.to_int()
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    (code >= 48 && code <= 57) ||
    character == '.' ||
    character == '_' ||
    character == ':' ||
    character == '-'
  })
}

///|
fn native_reviewer_cid(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:]
  .iter()
  .all(character => {
    let code = character.to_int()
    (code >= 48 && code <= 57) || (code >= 97 && code <= 102)
  })
}

///|
/// Decode only bounded, duplicate-free framing. The common Resolution Owner
/// supplies the signed preimage; it is not reconstructed with a new serializer.
fn native_reviewer_proof(
  wire : String,
  selected : NativeEffectReviewerSelection,
  limits : @checkpoint.WireLimits,
) -> NativeReviewerProof? {
  guard cloud_resume_query_label(selected.principal_id) &&
    native_reviewer_cid(selected.checkpoint_cid) else {
    return None
  }
  let preimage = match @checkpoint.resolution_proof_preimage(wire, limits) {
    Ok(value) => value
    Err(_) => return None
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  try {
    let root = cloud_resume_decoded(
      @decode.admit(source, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_wire_bytes,
        max_total_string_bytes: limits.max_wire_bytes,
      }),
    )
    let fields = cloud_resume_decoded(@decode.open_object(root))
    if cloud_resume_text(fields, "checkpoint_cid") != selected.checkpoint_cid {
      raise InvalidRead
    }
    let reviewer_id = cloud_resume_text(fields, "actor")
    let proof = cloud_resume_decoded(
      @decode.closed_object(
        cloud_resume_decoded(@decode.required(fields, "proof")),
        ["scheme", "key_id", "signature"],
      ),
    )
    let key_id = cloud_resume_text(proof, "key_id")
    if !native_reviewer_identifier(key_id) ||
      !native_reviewer_identifier(reviewer_id) ||
      cloud_resume_text(proof, "scheme") != "ed25519-v1" {
      raise InvalidRead
    }
    let signature = cloud_resume_text(proof, "signature")
    let bytes = @base64.decode(signature[:]) catch { _ => raise InvalidRead }
    if bytes.length() != 64 || @base64.encode(bytes) != signature {
      raise InvalidRead
    }
    Some({
      key_id,
      reviewer_id,
      preimage,
      signature_url: @base64.encode(bytes, padding=false)
      .replace_all(old="+", new="-")
      .replace_all(old="/", new="_"),
    })
  } catch {
    InvalidRead => None
  }
}

///|
fn native_reviewer_registration_matches(
  value : NativeEffectReviewerRegistration,
  selected : NativeEffectReviewerSelection,
  proof : NativeReviewerProof,
) -> Bool {
  value.selection == selected &&
  value.key_id == proof.key_id &&
  value.reviewer_id == proof.reviewer_id &&
  !value.public_key_pem.is_empty() &&
  @utf8.encode(value.public_key_pem).length() <= 4096 &&
  native_reviewer_cid(value.approval_authority_scope_cid) &&
  native_reviewer_cid(value.authority_context_cid) &&
  native_reviewer_cid(value.policy_cid)
}

///|
/// Private test seam for the synchronous physical verification boundary.
/// Production supplies only the installed Native signature implementation.
fn authenticate_native_reviewer_with(
  selected : NativeEffectReviewerSelection,
  resolution_wire : String,
  current_site : () -> Bool,
  read_current : (NativeEffectReviewerSelection, String) -> NativeEffectReviewerRegistration?,
  verify : (String, Bytes, String) -> Result[
    Bool,
    @signature.NativeSignatureIssue,
  ],
  limits : @checkpoint.WireLimits,
) -> Result[
  (@checkpoint.HostAuthentication, NativeEffectReviewerRegistration),
  NativeResidentEffectResolutionIssue,
] {
  if !current_site() {
    return Err(AuthorityDenied)
  }
  let proof = match native_reviewer_proof(resolution_wire, selected, limits) {
    Some(value) => value
    None => return Err(AttestationRejected)
  }
  let registered = match read_current(selected, proof.key_id) {
    Some(value) if native_reviewer_registration_matches(value, selected, proof) =>
      value
    _ => return Err(AuthorityDenied)
  }
  if !current_site() {
    return Err(AuthorityDenied)
  }
  match
    verify(
      registered.public_key_pem,
      @utf8.encode(proof.preimage),
      proof.signature_url,
    ) {
    Ok(true) => ()
    Ok(false) => return Err(AttestationRejected)
    Err(issue) => return Err(Signature(issue))
  }
  // Revocation, key rotation and principal/scope changes during either port
  // cannot turn a historical signature into current Reviewer authority.
  if !current_site() ||
    read_current(selected, proof.key_id) != Some(registered) ||
    !current_site() {
    return Err(AuthorityDenied)
  }
  Ok(
    (
      {
        key_id: registered.key_id,
        reviewer_id: registered.reviewer_id,
        expected_authority_scope_cid: registered.approval_authority_scope_cid,
        authority_context_cid: registered.authority_context_cid,
        policy_cid: registered.policy_cid,
        proof_preimage: proof.preimage,
      },
      registered,
    ),
  )
}

///|
/// Authenticate the exact Resolution proof with independently installed keys
/// and current original-principal authority. This supplies the existing Host
/// authentication port, not approval admission or a Provider-send permit.
/// The original Checkpoint, approval evidence, Host attestation, Resume fence
/// and current Provider authorization must still pass their existing Owners.
pub fn authenticate_native_effect_reviewer(
  installation : NativeEffectReviewerInstallation,
  selected : NativeEffectReviewerSelection,
  resolution_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@checkpoint.HostAuthentication, NativeResidentEffectResolutionIssue] {
  authenticate_native_reviewer_with(
    selected,
    resolution_wire,
    installation.current_site,
    installation.read_current,
    (key, bytes, signature) => {
      installation.crypto.verify_ed25519(key, bytes, signature)
    },
    limits,
  ).map(value => value.0)
}

///|
fn native_reviewer_canonical_value(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> @canonical.CanonicalValue? {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(
    @canonical.from_source(
      source,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    ),
  ) catch {
    _ => None
  }
}

///|
fn native_reviewer_canonical_wire(
  value : @canonical.CanonicalValue,
  limits : @checkpoint.WireLimits,
) -> String? {
  Some(
    @canonical.stringify_value(
      value,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ),
  ) catch {
    _ => None
  }
}

///|
fn native_reviewer_resolution_wire(
  verified_wire : String,
  limits : @checkpoint.WireLimits,
) -> String? {
  guard native_reviewer_canonical_value(verified_wire, limits) is Some(value) &&
    @canonical.object_field(value, "resolution") is Some(resolution) else {
    return None
  }
  native_reviewer_canonical_wire(resolution, limits)
}

///|
// Same physical verification boundary and current registration as the original
// Resolution port. Equality is complete canonical wire, including the actual
// proof and self identity, not just the unsigned proof preimage.
fn authenticate_native_wrapper_reviewer_with(
  selected : NativeEffectReviewerSelection,
  wrapper_wire : String,
  original_resolution_wire : String,
  current_site : () -> Bool,
  read_current : (NativeEffectReviewerSelection, String) -> NativeEffectReviewerRegistration?,
  verify : (String, Bytes, String) -> Result[
    Bool,
    @signature.NativeSignatureIssue,
  ],
  limits : @checkpoint.WireLimits,
) -> Result[
  (@checkpoint.HostAuthentication, NativeEffectReviewerRegistration),
  NativeResidentEffectResolutionIssue,
] {
  if !current_site() {
    return Err(AuthorityDenied)
  }
  guard native_reviewer_resolution_wire(wrapper_wire, limits) is Some(actual) &&
    native_reviewer_canonical_value(original_resolution_wire, limits)
    is Some(original) &&
    native_reviewer_canonical_wire(original, limits) == Some(actual) else {
    return Err(AttestationRejected)
  }
  authenticate_native_reviewer_with(
    selected, actual, current_site, read_current, verify, limits,
  )
}

///|
/// Authenticate the proof actually embedded in this proposed wrapper against
/// the complete retained signed Resolution. The wrapper is not trusted or
/// admitted here: independent Host signature, full common Checkpoint/evidence,
/// commit and resume gates remain mandatory. No key is selected from its wire.
pub fn authenticate_native_effect_wrapper_reviewer(
  installation : NativeEffectReviewerInstallation,
  selected : NativeEffectReviewerSelection,
  wrapper_wire : String,
  original_resolution_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@checkpoint.HostAuthentication, NativeResidentEffectResolutionIssue] {
  authenticate_native_wrapper_reviewer_with(
    selected,
    wrapper_wire,
    original_resolution_wire,
    installation.current_site,
    installation.read_current,
    (key, bytes, signature) => {
      installation.crypto.verify_ed25519(key, bytes, signature)
    },
    limits,
  ).map(value => value.0)
}

///|
/// Connect actual Reviewer verification to the retained original report/ACK
/// and the existing Common/Native Host attestation admission. The original
/// principal comes from independent Host custody, not from transport bytes.
/// This performs no claim, renewal, Provider send or Result publication.
pub fn NativeResidentEffectReview::authenticate_remote_reviewer(
  self : NativeResidentEffectReview,
  body : String,
  original_principal_id : String,
  installation : NativeEffectReviewerInstallation,
  host_authorities : Array[NativeEffectHostAuthority],
  current_authority : () -> Bool,
  now : () -> String,
) -> Result[@checkpoint.HostAuthentication, NativeResidentEffectResolutionIssue] {
  guard current_authority() &&
    (installation.current_site)() &&
    self.current() &&
    self.retention is Some(retention) &&
    self.retention_configuration is Some((_, _, _, _, _, limits)) else {
    return Err(Unavailable)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  if self.confirm_original_review_report(report, limits, true) is Err(_) {
    return Err(Unavailable)
  }
  let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
  let verified_wire = match native_reviewer_delivery_wire(body, limits) {
    Some(value) => value
    None => return Err(AttestationRejected)
  }
  let resolution_wire = match
    native_reviewer_resolution_wire(verified_wire, limits) {
    Some(value) => value
    None => return Err(AttestationRejected)
  }
  let selected : NativeEffectReviewerSelection = {
    principal_id: original_principal_id,
    checkpoint_cid: checkpoint.checkpoint_cid,
  }
  let (authentication, registered) = match
    authenticate_native_reviewer_with(
      selected,
      resolution_wire,
      installation.current_site,
      installation.read_current,
      (key, bytes, signature) => {
        installation.crypto.verify_ed25519(key, bytes, signature)
      },
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reviewers : Array[@checkpoint.ReviewerAuthority] = [
    { key_id: authentication.key_id, reviewer_id: authentication.reviewer_id, },
  ]
  // Only the existing original report Owner may admit the transported claim,
  // exact envelope bytes and Checkpoint/Resolution/intent identities.
  if @remote.admit_remote_effect_resume_delivery_json(
      body, report, authentication, reviewers, limits,
    )
    is Err(_) {
    return Err(AttestationRejected)
  }
  match
    self.admit_resolution(
      verified_wire,
      authentication,
      reviewers,
      host_authorities,
      () => {
        current_authority() &&
        (installation.current_site)() &&
        (installation.read_current)(selected, registered.key_id) ==
        Some(registered) &&
        (installation.current_site)() &&
        current_authority()
      },
      now,
    ) {
    Ok(_) => Ok(authentication)
    Err(issue) => Err(issue)
  }
}

///|
/// Framing extraction only, followed by the existing exact envelope admission.
fn native_reviewer_delivery_wire(
  body : String,
  limits : @checkpoint.WireLimits,
) -> String? {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(body), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  try {
    let root = cloud_resume_decoded(
      @decode.admit(source, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_wire_bytes,
        max_total_string_bytes: limits.max_wire_bytes,
      }),
    )
    let fields = cloud_resume_decoded(
      @decode.closed_object(root, [
        "checkpoint_cid", "claimant", "dispatch_request_cid", "generation", "report_cid",
        "resolution_cid", "resolution_wire", "resume_intent_id", "version",
      ]),
    )
    if cloud_resume_text(fields, "version") !=
      "actql-remote-effect-resume-delivery/0.1" {
      raise InvalidRead
    }
    Some(cloud_resume_text(fields, "resolution_wire"))
  } catch {
    InvalidRead => None
  }
}
