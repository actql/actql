///|
/// Retained occurrence in the existing authenticated capture Read. This view
/// grants neither Source access nor physical byte custody; the Store issuer
/// and parent reader continue to own those responsibilities.
priv struct RecoveredClientEffectSourceCommandContentOriginal {
  source_original : ClientEffectKeyedOriginal
  owner : PreparedClientEffectComputation
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  captured : @publication.PublicationContract
  preview : @publication.EffectPreviewIdentity
  candidate : ClientCapturedContent
  reference : @values.ReferenceValue
  member_index : Int
  row : Int
  input_name : String
}

///|
struct RecoveredClientEffectSourceCommandContent {
  mut original : RecoveredClientEffectSourceCommandContentOriginal?
}

///|
fn recovered_source_context_current(
  original : ClientEffectKeyedOriginal,
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
) -> Bool {
  physical_equal(original.prepared, owner) &&
  physical_equal(original.request, request) &&
  client_effect_keyed_original_current(original)
}

///|
/// DATA from the exact original checked Source. An equal Request envelope is
/// insufficient; this is the managed parent's retained nominal occurrence.
pub fn client_effect_keyed_original_source_evidence_facts(
  original : ClientEffectKeyedOriginal,
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
) -> Result[Array[String], ClientEffectCommandContentIssue] {
  guard recovered_source_context_current(original, owner, request) &&
    client_keyed_acquisition_source_evidence_facts(original.keyed)
    is Some(facts) else {
    return Err(ForeignInput)
  }
  Ok(@planning.query_source_evidence_fact_values(facts))
}

///|
/// Restore the Source candidate through the SAME compiled/definition/keyed
/// original. Authenticated row association and physical Store custody are
/// independently required before this candidate becomes a Command input.
pub fn prepare_client_recovered_source_content_candidate(
  original : ClientEffectKeyedOriginal,
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
  reference_wire : String,
  binding_wire : String,
  limits : @values.ReferenceLimits,
) -> Result[ClientCapturedContent, @publication.GeneratedContentReferenceIssue] {
  if !recovered_source_context_current(original, owner, request) {
    return Err(InvalidBinding("source_original"))
  }
  prepare_client_stored_run_captured_content(
    original.compiled,
    original.definition,
    original.keyed,
    reference_wire,
    binding_wire,
    limits,
  )
}

///|
fn recovered_source_candidate_matches(
  original : ClientEffectKeyedOriginal,
  candidate : ClientCapturedContent,
) -> Bool {
  physical_equal(candidate.acquisition, original.keyed) &&
  candidate.request is None &&
  candidate.run_definition.map(definition => {
    physical_equal(definition, original.definition)
  }) ==
  Some(true)
}

///|
/// The caller re-enters its original captured Read constructor before this
/// inverse. No live Source attempt, Model token or serialization is recreated.
pub fn readmit_client_effect_source_command_content(
  original : ClientEffectKeyedOriginal,
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  invocation : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  store_authority_cid : String,
  member_index : Int,
  row : Int,
  input_name : String,
  candidate : ClientCapturedContent,
  content : @values.CheckedValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  RecoveredClientEffectSourceCommandContent,
  ClientEffectCommandContentIssue,
] {
  if !recovered_source_context_current(original, owner, request) ||
    !recovered_source_candidate_matches(original, candidate) ||
    @publication.publication_contract_json(definition) !=
    @publication.publication_contract_json(original.definition) {
    return Err(ForeignInput)
  }
  if member_index < 0 ||
    row < 0 ||
    max_fields < 0 ||
    max_work < 0 ||
    max_bytes < 0 ||
    max_nodes < 0 ||
    max_depth < 0 {
    return Err(InvalidLimits)
  }
  if client_compiled_effect_program(original.compiled, owner) is None ||
    check_client_compiled_run_definition(original.compiled, definition)
    is Err(_) ||
    @publication.effect_preview_program_definition_cid(preview) !=
    prepared_client_effect_computation_definition_cid(owner) ||
    @publication.effect_preview_program_semantics_cid(preview) !=
    prepared_client_effect_computation_semantics_cid(owner) ||
    @publication.effect_preview_check_environment_cid(preview) !=
    prepared_client_effect_computation_environment_cid(owner) {
    return Err(ForeignInput)
  }
  // These limits belong to the SAME admitted capture, not one Command body.
  // The Read owner re-enters its original funded constructor before this
  // inverse. Keep the caller's row/reference bounds for the later row parse.
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_at(headers, member_index) is Some(header) &&
    @publication.effect_preview_member_effect_id(preview, member_index) ==
    Some(@syntax.effect_header_id(header)) &&
    @publication.effect_preview_member_kind(preview, member_index) ==
    Some("command") &&
    @publication.captured_effect_source_result_from_original_capture(
      preview, member_index, invocation, source, captured, store_authority_cid,
    )
    is Ok(_) else {
    return Err(ForeignInput)
  }
  let commands = @stage_results.effect_static_candidate_command_inputs(
    @checked.effect_program_static_effects(owner.candidate),
  )
  let count = @stage_results.effect_command_input_count(commands)
  if max_work == 0 || count > max_work - 1 || input_name.length() > max_work {
    return Err(Limit)
  }
  let command = match
    @stage_results.effect_command_input_for_member(
      commands, member_index, max_work,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(MissingContentInput)
    Err(issue) => return Err(Command(issue))
  }
  let fields = @stage_results.effect_command_input_field_count(command)
  if fields > max_fields || fields > max_work - count - 1 {
    return Err(Limit)
  }
  let mut selected = false
  let mut remaining = max_work - count - fields - 1
  for index in 0..<fields {
    let field = @stage_results.effect_command_input_field_at(command, index).unwrap()
    let name = @stage_results.effect_command_input_field_name(field)
    if name.length() > remaining {
      return Err(Limit)
    }
    remaining -= name.length()
    if name == input_name {
      selected = @stage_results.effect_command_input_field_contract(field).shape
        is @contract.ContentRef(..) &&
        @stage_results.effect_command_input_field_value(field)
        is @stage_results.ResultField(_)
    }
  }
  if !selected {
    return Err(MissingContentInput)
  }
  guard @publication.effect_preview_row_intended_value_wire(
      preview, member_index, row,
    )
    is Some(row_wire) &&
    parse_plan_identity_value(row_wire, max_bytes, max_nodes, max_depth)
    is Some(value) &&
    @canonical.object_field(value, input_name) is Some(expected) &&
    content.value is @values.Reference(reference) else {
    return Err(ForeignInput)
  }
  let expected_wire = @canonical.stringify_value(
    expected, max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Limit)
  }
  if expected_wire != @values.reference_wire(reference) {
    return Err(ForeignInput)
  }
  if expected_wire != client_captured_content_wire(candidate) ||
    !recovered_source_context_current(original, owner, request) {
    return Err(ForeignInput)
  }
  let result : RecoveredClientEffectSourceCommandContent = {
    original: Some({
      source_original: original,
      owner,
      request,
      definition,
      captured,
      preview,
      candidate,
      reference,
      member_index,
      row,
      input_name,
    }),
  }
  if !recovered_client_effect_source_command_content_current(result) {
    return Err(Unavailable)
  }
  Ok(result)
}

///|
pub fn recovered_client_effect_source_command_content_current(
  value : RecoveredClientEffectSourceCommandContent,
) -> Bool {
  guard value.original is Some(original) else { return false }
  recovered_source_context_current(
    original.source_original,
    original.owner,
    original.request,
  ) &&
  recovered_source_candidate_matches(
    original.source_original,
    original.candidate,
  ) &&
  @values.reference_available(original.reference) &&
  recovered_source_context_current(
    original.source_original,
    original.owner,
    original.request,
  ) &&
  value.original.map(current => physical_equal(current, original)) == Some(true)
}

///|
pub fn recovered_client_effect_source_command_content_matches(
  value : RecoveredClientEffectSourceCommandContent,
  source_original : ClientEffectKeyedOriginal,
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row : Int,
  input_name : String,
) -> Bool {
  guard value.original is Some(original) else { return false }
  physical_equal(original.source_original, source_original) &&
  physical_equal(original.owner, owner) &&
  physical_equal(original.request, request) &&
  physical_equal(original.definition, definition) &&
  physical_equal(original.captured, captured) &&
  physical_equal(original.preview, preview) &&
  original.member_index == member_index &&
  original.row == row &&
  original.input_name == input_name &&
  recovered_client_effect_source_command_content_current(value)
}

///|
pub fn recovered_client_effect_source_command_content_matches_issued(
  value : RecoveredClientEffectSourceCommandContent,
  content : @values.CheckedValue,
) -> Bool {
  guard value.original is Some(original) &&
    content.value is @values.Reference(reference) else {
    return false
  }
  physical_equal(reference, original.reference) &&
  recovered_client_effect_source_command_content_current(value)
}

///|
pub fn recovered_client_effect_source_command_content_wire(
  value : RecoveredClientEffectSourceCommandContent,
) -> Result[String, ClientEffectCommandContentIssue] {
  if !recovered_client_effect_source_command_content_current(value) {
    return Err(Unavailable)
  }
  guard value.original is Some(original) else { return Err(Unavailable) }
  Ok(@values.reference_wire(original.reference))
}

///|
/// Release this alias only. The original parent owns readers and holdings.
pub fn release_recovered_client_effect_source_command_content(
  value : RecoveredClientEffectSourceCommandContent,
) -> Unit {
  value.original = None
}
