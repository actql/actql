///|
/// Candidate provenance borrows the original checked keyed Source request.
/// It is not another acquisition, ledger, byte owner or Source completion.
struct ClientCapturedContent {
  acquisition : ClientKeyedAcquisition
  request : ClientKeyedRequest?
  candidate : @publication.CapturedContentReference
  run_definition : @publication.PublicationContract?
  capture_authority_cid : String
}

///|
fn client_captured_content_schema_media_matches(
  schema : @schema.Schema,
  observed_media_type : String,
) -> Bool {
  let mut contents = 0
  for field in @schema.fields(schema) {
    if field.contract.shape is @contract.ContentRef(media_type=expected) {
      if expected is Some(required) && required != observed_media_type {
        return false
      }
      contents += 1
    }
  }
  contents == 1
}

///|
pub fn prepare_client_captured_content(
  acquisition : ClientKeyedAcquisition,
  request : ClientKeyedRequest,
  binding_wire : String,
  media_type : String,
  content_cid : String,
  size_bytes : Int,
  limits : @values.ReferenceLimits,
) -> Result[ClientCapturedContent, @publication.GeneratedContentReferenceIssue] {
  if !client_keyed_request_matches_acquisition(request, acquisition) ||
    request.attempts < 1L ||
    request.io_complete ||
    request.left.lookup_issue is Some(_) {
    return Err(InvalidBinding("source_request"))
  }
  guard client_keyed_acquisition_source_evidence_facts(acquisition)
    is Some(facts) else {
    return Err(InvalidBinding("source_facts"))
  }
  let binding = match
    @publication.parse_content_reference_binding(binding_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if binding.effective_data_policy_cid != facts.source_data_policy_cid ||
    binding.data_classification != facts.data_classification {
    return Err(InvalidBinding("source_policy"))
  }
  let observed_media_type = match
    @contract.normalize_content_media_type_case(media_type, 256) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding("reported_media_type"))
  }
  let schema = match
    @query.keyed_response_input_schema(
      acquisition.owner,
      acquisition.binding.join,
      request.request,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding("source_schema"))
  }
  // The declared Content column may leave MIME unrefined. Its actual report
  // is still validated above and retained below; a declared refinement must
  // match. Provider metadata cannot invent or narrow that Source contract.
  if !client_captured_content_schema_media_matches(schema, observed_media_type) {
    return Err(InvalidBinding("source_media_type"))
  }
  @publication.prepare_captured_content_reference(
    binding, media_type, content_cid, size_bytes, limits,
  ).map(candidate => {
    acquisition,
    request: Some(request),
    candidate,
    run_definition: None,
    capture_authority_cid: binding.capture_authority_cid,
  })
}

///|
/// Installed capture keeps the original compilation and its admitted lifetime.
/// A compatible independently prepared Program or renewed definition cannot
/// substitute for this Run. The generic candidate is still used by isolated
/// Source adapters; production dispatch uses this Run-bound entry point.
pub fn prepare_client_run_captured_content(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  acquisition : ClientKeyedAcquisition,
  request : ClientKeyedRequest,
  binding_wire : String,
  media_type : String,
  content_cid : String,
  size_bytes : Int,
  limits : @values.ReferenceLimits,
) -> Result[ClientCapturedContent, @publication.GeneratedContentReferenceIssue] {
  let matches = match compiled.compilation {
    Effects(allowed) =>
      client_keyed_acquisition_matches_effect_program(
        acquisition,
        allowed.compilation.owner,
      )
    _ => client_keyed_acquisition_matches_program(acquisition, compiled.owner)
  }
  if !matches ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(InvalidBinding("source_run"))
  }
  let binding = match
    @publication.parse_content_reference_binding(binding_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @publication.run_definition_lifetime(definition) is Some((_, until)) &&
    binding.expires_at == Some(until) else {
    return Err(InvalidBinding("source_run_lifetime"))
  }
  prepare_client_captured_content(
    acquisition, request, binding_wire, media_type, content_cid, size_bytes, limits,
  ).map(value => { ..value, run_definition: Some(definition), })
}

///|
/// Restore only the reference metadata bound to this reconstructed original
/// Run and checked Source port. Authenticated inventory and physical byte
/// custody still belong to the installing Host/Store and ReferenceIssuer.
/// In particular, this does not manufacture a request, attempt or completion.
pub fn prepare_client_stored_run_captured_content(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  acquisition : ClientKeyedAcquisition,
  original_wire : String,
  binding_wire : String,
  limits : @values.ReferenceLimits,
) -> Result[ClientCapturedContent, @publication.GeneratedContentReferenceIssue] {
  let matches = match compiled.compilation {
    Effects(allowed) =>
      client_keyed_acquisition_matches_effect_program(
        acquisition,
        allowed.compilation.owner,
      )
    _ => client_keyed_acquisition_matches_program(acquisition, compiled.owner)
  }
  if !matches ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(InvalidBinding("source_run"))
  }
  let binding = match
    @publication.parse_content_reference_binding(binding_wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @publication.run_definition_lifetime(definition) is Some((_, until)) &&
    binding.expires_at == Some(until) else {
    return Err(InvalidBinding("source_run_lifetime"))
  }
  guard client_keyed_acquisition_source_evidence_facts(acquisition)
    is Some(facts) else {
    return Err(InvalidBinding("source_facts"))
  }
  if binding.effective_data_policy_cid != facts.source_data_policy_cid ||
    binding.data_classification != facts.data_classification {
    return Err(InvalidBinding("source_policy"))
  }
  let candidate = match
    @publication.prepare_stored_captured_content_reference(
      original_wire, binding, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let schema = match
    @query.keyed_response_port_schema(
      acquisition.owner,
      acquisition.binding.join,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding("source_schema"))
  }
  // The candidate reconstructed its full original report and envelope. Check
  // its projected MIME against the original checked response, without issuing
  // a second candidate from that expected string and discarding the report.
  let media_type = @publication.captured_content_reference_media_type(candidate)
  if !client_captured_content_schema_media_matches(schema, media_type) {
    return Err(InvalidBinding("source_media_type"))
  }
  Ok({
    acquisition,
    request: None,
    candidate,
    run_definition: Some(definition),
    capture_authority_cid: binding.capture_authority_cid,
  })
}

///|
/// The existing physical Store retains one exact capture for the original Run.
/// This private holding identity is distinct from byte CID and Ref CID.
pub fn client_captured_content_holding_cid(
  value : ClientCapturedContent,
) -> String? {
  guard value.run_definition is Some(definition) else { return None }
  let (store, _, _, _) = client_captured_content_storage(value)
  try {
    let writer = @encode.hashing_writer(2048, 64, 2)
    @encode.begin_object(writer)
    for
      (key, item) in [
        ("capture_authority_cid", value.capture_authority_cid),
        ("content_ref_cid", client_captured_content_identity(value)),
        ("role", "captured_content_bytes"),
        (
          "run_definition_cid",
          @publication.publication_contract_identity(definition),
        ),
        ("store_authority_cid", store),
        ("version", "actql-content-private-holding/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, item)
    }
    @encode.end_object(writer)
    Some("sha256:" + @encode.finish_hash(writer))
  } catch {
    _ => None
  }
}

///|
/// One sequential capture frame overlaps canonical candidate/issued/row wire,
/// bounded JSON trees and the original Store handles. Completed rows retain
/// their own charged values; this frame also retains the bounded original
/// reference inventory used by the existing fixed-input continuation.
/// These are conservative logical slots, not an allocator or RSS claim.
pub fn client_captured_content_workspace_capacity(
  max_bytes : Int,
  inventory_count? : Int = 0,
) -> (Int64, Int64)? {
  if max_bytes < 1 || max_bytes > 1048576 || inventory_count < 0 {
    return None
  }
  let wires = max_bytes.to_int64() * 8L
  let trees = 256L * 64L
  let control_slots = 32L * 8L
  // Original wire, admitted reference, index entry and snapshot copy overlap
  // until the existing Model input receipt commits. This is the inventory
  // capacity being admitted now, not a declaration that unseen keys exist.
  // The original workspace grows before each new retained entry is built.
  let inventory = inventory_count.to_int64() * (wires + trees + 1024L)
  Some(
    (
      wires + trees + control_slots + inventory,
      wires + trees + 4096L + inventory,
    ),
  )
}

///|
pub fn client_captured_content_wire(value : ClientCapturedContent) -> String {
  @publication.captured_content_reference_wire(value.candidate)
}

///|
pub fn client_captured_content_identity(
  value : ClientCapturedContent,
) -> String {
  @publication.captured_content_reference_identity(value.candidate)
}

///|
pub fn client_captured_content_storage(
  value : ClientCapturedContent,
) -> (String, String, String, Int) {
  @publication.captured_content_reference_storage(value.candidate)
}

///|
pub fn issue_client_captured_content(
  value : ClientCapturedContent,
  issuer : @values.ReferenceIssuer,
  limits : @values.ReferenceLimits,
) -> Result[@values.CheckedValue, @publication.GeneratedContentReferenceIssue] {
  if value.request is Some(request) {
    if !client_keyed_request_matches_acquisition(request, value.acquisition) ||
      request.left.lookup_issue is Some(_) {
      return Err(InvalidBinding("source_request"))
    }
  } else if value.run_definition is None {
    return Err(InvalidBinding("source_run"))
  }
  @publication.issue_captured_content_reference(value.candidate, issuer, limits)
}
