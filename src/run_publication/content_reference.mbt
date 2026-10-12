///|
/// A trusted Host supplies these binding facts after selecting the existing
/// holding, policy and issuer owners. They describe a candidate, not authority:
/// the ReferenceIssuer must verify actual durable byte custody before issuance.
pub(all) struct GeneratedContentBinding {
  content_store_id : String
  content_store_cid : String
  workspace_scope_cid : String
  storage_scope : String
  retention_class : String
  expires_at : String?
  availability_evidence_cid : String
  effective_data_policy_cid : String
  data_classification : String
  issuer_contract_cid : String
  capture_authority_cid : String
}

///|
/// The common owner constructs the canonical candidate from its own completed
/// byte generation. A candidate cannot be used as an opaque admitted value.
struct GeneratedContentReference {
  owner : ContentByteEncoder
  wire : String
  envelope : @json.CanonicalValue
  identity : String
  issuer_evidence_cid : String
  completion : ContentByteCompletion
  binding : GeneratedContentBinding
}

///|
pub(all) enum GeneratedContentReferenceIssue {
  GenerationIncomplete
  InvalidBinding(String)
  Encoding
  Issuance(@admitted.ReferenceIssue)
} derive(Eq, Debug)

///|
fn seal_content_identity(
  wire : String,
  identity_field : String,
  limits : @admitted.ReferenceLimits,
) -> Result[(@json.CanonicalValue, String), GeneratedContentReferenceIssue] {
  let body = match
    parse_contract_wire(
      wire,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let identity = @json.cid_value(
    body,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  guard @json.object_with_string_field(body, identity_field, identity)
    is Some(identified) else {
    return Err(Encoding)
  }
  Ok((identified, identity))
}

///|
pub fn prepare_generated_content_reference(
  owner : ContentByteEncoder,
  binding : GeneratedContentBinding,
  limits : @admitted.ReferenceLimits,
) -> Result[GeneratedContentReference, GeneratedContentReferenceIssue] {
  // Never accept a caller-authored completion in place of this encoder's bytes.
  guard owner.phase == 90 && owner.completion is Some(completion) else {
    return Err(GenerationIncomplete)
  }
  prepare_content_reference_body(
    binding,
    completion.media_type,
    completion.content_cid,
    completion.size_bytes,
    "content_derivation",
    limits,
  ).map(body => {
    owner,
    wire: body.wire,
    envelope: body.envelope,
    identity: body.identity,
    issuer_evidence_cid: body.issuer_evidence_cid,
    completion,
    binding,
  })
}

///|
/// Shared canonical construction for derivation and connector capture. This
/// sealed candidate is not byte custody or Source completion; the existing
/// issuer still verifies the physical Store before admitting an opaque value.
priv struct ContentReferenceBody {
  wire : String
  envelope : @json.CanonicalValue
  identity : String
  issuer_evidence_cid : String
}

///|
/// A saved canonical reference checked against the installing Host's original
/// binding. This is not a byte generation or a completion token: the existing
/// ReferenceIssuer must independently confirm durable bytes and current access.
struct StoredGeneratedContentReference {
  body : ContentReferenceBody
  binding : GeneratedContentBinding
  media_type : String
  content_cid : String
  size_bytes : Int
}

///|
/// Reconstruct the reference preimage, not its bytes. Exact comparison prevents
/// recovery from relabeling a saved holding, renewing its lifetime or accepting
/// extra metadata. No encoder is fabricated and no input is acquired here.
pub fn prepare_stored_generated_content_reference(
  original_wire : String,
  binding : GeneratedContentBinding,
  limits : @admitted.ReferenceLimits,
) -> Result[StoredGeneratedContentReference, GeneratedContentReferenceIssue] {
  stored_content_reference_parts(
    original_wire, binding, "content_derivation", limits,
  ).map(parts => {
    let (body, media_type, content_cid, size_bytes) = parts
    { body, binding, media_type, content_cid, size_bytes, }
  })
}

///|
/// Both provenances reconstruct the same closed canonical body. The caller
/// fixes the issuer kind; a saved envelope cannot switch capture to generation.
fn stored_content_reference_parts(
  original_wire : String,
  binding : GeneratedContentBinding,
  issuer_kind : String,
  limits : @admitted.ReferenceLimits,
) -> Result[
  (ContentReferenceBody, String, String, Int),
  GeneratedContentReferenceIssue,
] {
  let original = match
    parse_contract_wire(
      original_wire,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  guard @json.object_field(original, "metadata") is Some(metadata) &&
    contract_string_from_value(original, "media_type") is Some(media_type) &&
    contract_string_from_value(metadata, "content_cid") is Some(content_cid) &&
    @json.object_field(metadata, "size_bytes") is Some(@json.Number(size)) &&
    size >= 0 &&
    size <= 2147483647.0 &&
    size == size.to_int().to_double() else {
    return Err(InvalidBinding("saved_reference"))
  }
  let size_bytes = size.to_int()
  let body = match
    prepare_content_reference_body(
      binding, media_type, content_cid, size_bytes, issuer_kind, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if body.wire != original_wire {
    return Err(InvalidBinding("saved_reference"))
  }
  Ok((body, media_type, content_cid, size_bytes))
}

///|
pub fn stored_generated_content_reference_wire(
  candidate : StoredGeneratedContentReference,
) -> String {
  candidate.body.wire
}

///|
pub fn stored_generated_content_reference_storage(
  candidate : StoredGeneratedContentReference,
) -> (String, String, String, String, Int) {
  (
    candidate.body.identity,
    candidate.binding.content_store_cid,
    candidate.binding.workspace_scope_cid,
    candidate.content_cid,
    candidate.size_bytes,
  )
}

///|
/// Saved metadata is not authority. This uses the same issuer boundary as a
/// fresh generation, without permitting the saved candidate to claim encoding.
pub fn issue_stored_generated_content_reference(
  candidate : StoredGeneratedContentReference,
  issuer : @admitted.ReferenceIssuer,
  limits : @admitted.ReferenceLimits,
) -> Result[@admitted.CheckedValue, GeneratedContentReferenceIssue] {
  let contract = @contract.content_reference_contract(
    Some(candidate.media_type),
    nullable=false,
    max_name_bytes=256,
  ).unwrap()
  @admitted.issue_reference(issuer, contract, candidate.body.wire, limits).map_err(issue => {
      Issuance(issue)
    },
  )
}

///|
fn prepare_content_reference_body(
  binding : GeneratedContentBinding,
  media_type : String,
  content_cid : String,
  size_bytes : Int,
  issuer_kind : String,
  limits : @admitted.ReferenceLimits,
) -> Result[ContentReferenceBody, GeneratedContentReferenceIssue] {
  if !valid_contract_cid(content_cid) || size_bytes < 0 {
    return Err(InvalidBinding("content_bytes"))
  }
  if @contract.content_reference_contract(
      Some(media_type),
      nullable=false,
      max_name_bytes=256,
    )
    is None {
    return Err(InvalidBinding("media_type"))
  }
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_text_units < 1 {
    return Err(Encoding)
  }
  for
    (name, value) in [
      ("content_store_cid", binding.content_store_cid),
      ("workspace_scope_cid", binding.workspace_scope_cid),
      ("availability_evidence_cid", binding.availability_evidence_cid),
      ("effective_data_policy_cid", binding.effective_data_policy_cid),
      ("issuer_contract_cid", binding.issuer_contract_cid),
      ("capture_authority_cid", binding.capture_authority_cid),
    ] {
    if !valid_contract_cid(value) {
      return Err(InvalidBinding(name))
    }
  }
  for
    (name, value) in [
      ("content_store_id", binding.content_store_id),
      ("retention_class", binding.retention_class),
    ] {
    if value.is_empty() || value.length() > limits.max_text_units {
      return Err(InvalidBinding(name))
    }
  }
  if !["run", "local", "workspace"].contains(binding.storage_scope) {
    return Err(InvalidBinding("storage_scope"))
  }
  if !["public", "internal", "confidential", "restricted", "unknown"].contains(
      binding.data_classification,
    ) {
    return Err(InvalidBinding("data_classification"))
  }
  if binding.expires_at is Some(time) && !valid_timestamp(time) {
    return Err(InvalidBinding("expires_at"))
  }
  let issuer_writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let issuer_body = try {
    @encode.begin_object(issuer_writer)
    for
      (key, value) in [
        ("version", "actql-content-issuer-evidence/0.1"),
        ("issuer_kind", issuer_kind),
        ("issuer_contract_cid", binding.issuer_contract_cid),
        ("content_store_cid", binding.content_store_cid),
        ("workspace_scope_cid", binding.workspace_scope_cid),
        ("content_cid", content_cid),
        ("effective_data_policy_cid", binding.effective_data_policy_cid),
        ("capture_authority_cid", binding.capture_authority_cid),
      ] {
      @encode.key(issuer_writer, key)
      @encode.string_value(issuer_writer, value)
    }
    @encode.end_object(issuer_writer)
    @encode.finish(issuer_writer)
  } catch {
    _ => return Err(Encoding)
  }
  let (issuer, issuer_cid) = match
    seal_content_identity(issuer_body, "evidence_cid", limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let body = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("$actql_ref", "content"),
        ("version", "actql-content-ref/0.1"),
        ("media_type", media_type),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "metadata")
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("content_store_id", binding.content_store_id),
        ("content_cid", content_cid),
        ("media_type", media_type),
        ("storage_scope", binding.storage_scope),
        ("retention_class", binding.retention_class),
        ("availability_evidence_cid", binding.availability_evidence_cid),
        ("capture_authority", "read_content"),
        ("data_classification", binding.data_classification),
        ("effective_data_policy_cid", binding.effective_data_policy_cid),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    if binding.expires_at is Some(time) {
      @encode.key(writer, "expires_at")
      @encode.string_value(writer, time)
    }
    @encode.key(writer, "size_bytes")
    @encode.number_value(writer, size_bytes.to_double())
    @encode.key(writer, "truncated")
    @encode.bool_value(writer, false)
    @encode.key(writer, "issuer_evidence")
    @json.emit_value(issuer, writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let (identified, identity) = match
    seal_content_identity(body, "content_ref_cid", limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = @json.stringify_value(
    identified,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  Ok({ wire, envelope: identified, identity, issuer_evidence_cid: issuer_cid, })
}

///|
/// Exact generation provenance, not equality of byte hashes. A candidate from
/// another generation cannot stand in for this input's completed byte cursor.
pub fn generated_content_reference_completion_for(
  candidate : GeneratedContentReference,
  owner : ContentByteEncoder,
) -> ContentByteCompletion? {
  if !physical_equal(candidate.owner, owner) || owner.phase != 90 {
    return None
  }
  Some(candidate.completion)
}

///|
/// Internal Host transport of selected binding facts, never an author-provided
/// reference envelope. The same typed preparation and issuer boundary apply.
pub fn prepare_generated_content_reference_from_binding(
  owner : ContentByteEncoder,
  binding_wire : String,
  limits : @admitted.ReferenceLimits,
) -> Result[GeneratedContentReference, GeneratedContentReferenceIssue] {
  let binding = match parse_content_reference_binding(binding_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  prepare_generated_content_reference(owner, binding, limits)
}

///|
pub fn parse_content_reference_binding(
  binding_wire : String,
  limits : @admitted.ReferenceLimits,
) -> Result[GeneratedContentBinding, GeneratedContentReferenceIssue] {
  let value = match
    parse_contract_wire(
      binding_wire,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let required = [
    "content_store_id", "content_store_cid", "workspace_scope_cid", "storage_scope",
    "retention_class", "availability_evidence_cid", "effective_data_policy_cid",
    "data_classification", "issuer_contract_cid", "capture_authority_cid",
  ]
  guard @json.object_fields(value) is Some(fields) else {
    return Err(InvalidBinding("binding"))
  }
  for (key, _) in fields {
    if !required.contains(key) && key != "expires_at" {
      return Err(InvalidBinding(key))
    }
  }
  let get = name => contract_string_from_value(value, name)
  for key in required {
    if get(key) is None {
      return Err(InvalidBinding(key))
    }
  }
  let expires = match @json.object_field(value, "expires_at") {
    None => None
    Some(@json.String(time)) => Some(time)
    _ => return Err(InvalidBinding("expires_at"))
  }
  Ok({
    content_store_id: get("content_store_id").unwrap(),
    content_store_cid: get("content_store_cid").unwrap(),
    workspace_scope_cid: get("workspace_scope_cid").unwrap(),
    storage_scope: get("storage_scope").unwrap(),
    retention_class: get("retention_class").unwrap(),
    expires_at: expires,
    availability_evidence_cid: get("availability_evidence_cid").unwrap(),
    effective_data_policy_cid: get("effective_data_policy_cid").unwrap(),
    data_classification: get("data_classification").unwrap(),
    issuer_contract_cid: get("issuer_contract_cid").unwrap(),
    capture_authority_cid: get("capture_authority_cid").unwrap(),
  })
}

///|
pub fn generated_content_reference_storage(
  candidate : GeneratedContentReference,
) -> (String, String, String, Int) {
  (
    candidate.binding.content_store_cid,
    candidate.binding.workspace_scope_cid,
    candidate.completion.content_cid,
    candidate.completion.size_bytes,
  )
}

///|
/// The exact policy original selected for these generated bytes. A later
/// compiled Run cannot relabel custody under another effective policy.
pub fn generated_content_reference_policy(
  candidate : GeneratedContentReference,
) -> String {
  candidate.binding.effective_data_policy_cid
}

///|
/// The same existing issuer decides durable custody and current authorization.
/// Rejection leaves the candidate available for an exact retry after the Store
/// fact is confirmed; it never regenerates bytes or manufactures authority.
pub fn issue_generated_content_reference(
  candidate : GeneratedContentReference,
  issuer : @admitted.ReferenceIssuer,
  limits : @admitted.ReferenceLimits,
) -> Result[@admitted.CheckedValue, GeneratedContentReferenceIssue] {
  let contract = @contract.content_reference_contract(
    Some(candidate.completion.media_type),
    nullable=false,
    max_name_bytes=256,
  ).unwrap()
  @admitted.issue_reference(issuer, contract, candidate.wire, limits).map_err(issue => {
    Issuance(issue)
  })
}

///|
pub fn generated_content_reference_wire(
  candidate : GeneratedContentReference,
) -> String {
  candidate.wire
}

///|
pub fn generated_content_reference_identity(
  candidate : GeneratedContentReference,
) -> String {
  candidate.identity
}

///|
pub fn generated_content_issuer_evidence_cid(
  candidate : GeneratedContentReference,
) -> String {
  candidate.issuer_evidence_cid
}

///|
/// A trusted physical capture supplies verified byte facts. This is a sealed
/// candidate only, not a new capture owner and not an admitted ContentRef.
/// The checked Source owner binds its request/policy before construction, and
/// ReferenceIssuer verifies durable Store custody before issuance.
struct CapturedContentReference {
  body : ContentReferenceBody
  binding : GeneratedContentBinding
  media_type : String
  content_cid : String
  size_bytes : Int
}

///|
pub fn prepare_captured_content_reference(
  binding : GeneratedContentBinding,
  media_type : String,
  content_cid : String,
  size_bytes : Int,
  limits : @admitted.ReferenceLimits,
) -> Result[CapturedContentReference, GeneratedContentReferenceIssue] {
  prepare_content_reference_body(
    binding, media_type, content_cid, size_bytes, "connector_capture", limits,
  ).map(body => { body, binding, media_type, content_cid, size_bytes, })
}

///|
/// Recover metadata only, without provider access or a fabricated acquisition.
/// The existing issuer must separately verify the original durable holding and
/// current authority. No lifetime, policy or capture binding is repaired here.
pub fn prepare_stored_captured_content_reference(
  original_wire : String,
  binding : GeneratedContentBinding,
  limits : @admitted.ReferenceLimits,
) -> Result[CapturedContentReference, GeneratedContentReferenceIssue] {
  stored_content_reference_parts(
    original_wire, binding, "connector_capture", limits,
  ).map(parts => {
    let (body, media_type, content_cid, size_bytes) = parts
    { body, binding, media_type, content_cid, size_bytes, }
  })
}

///|
pub fn captured_content_reference_storage(
  candidate : CapturedContentReference,
) -> (String, String, String, Int) {
  (
    candidate.binding.content_store_cid,
    candidate.binding.workspace_scope_cid,
    candidate.content_cid,
    candidate.size_bytes,
  )
}

///|
pub fn captured_content_reference_wire(
  candidate : CapturedContentReference,
) -> String {
  candidate.body.wire
}

///|
pub fn captured_content_reference_identity(
  candidate : CapturedContentReference,
) -> String {
  candidate.body.identity
}

///|
pub fn issue_captured_content_reference(
  candidate : CapturedContentReference,
  issuer : @admitted.ReferenceIssuer,
  limits : @admitted.ReferenceLimits,
) -> Result[@admitted.CheckedValue, GeneratedContentReferenceIssue] {
  let contract = @contract.content_reference_contract(
    Some(candidate.media_type),
    nullable=false,
    max_name_bytes=256,
  ).unwrap()
  @admitted.issue_reference(issuer, contract, candidate.body.wire, limits).map_err(issue => {
      Issuance(issue)
    },
  )
}
