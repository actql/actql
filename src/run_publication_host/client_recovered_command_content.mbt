///|
/// A recovered view in the existing Command input owner. It retains a newly
/// validated local handle to the saved original; it is not a live Compute pin,
/// a replacement generation, byte custody or a shared-workspace borrower.
priv struct RecoveredClientEffectCommandContentOriginal {
  run : ClientCompiledRun
  owner : PreparedClientEffectComputation
  definition : @publication.PublicationContract
  captured : @publication.PublicationContract
  preview : @publication.EffectPreviewIdentity
  generation : @publication.BoundContentGeneration
  reference : @values.ReferenceValue
  member_index : Int
  row : Int
  input_name : String
}

///|
struct RecoveredClientEffectCommandContent {
  mut original : RecoveredClientEffectCommandContentOriginal?
}

///|
/// Recover only through the same compiled Run and authenticated capture/member.
/// The Store independently confirms the original holding and issues `content`;
/// equal envelope bytes alone do not reconstruct that physical responsibility.
pub fn readmit_client_effect_command_content(
  run : ClientCompiledRun,
  owner : PreparedClientEffectComputation,
  definition : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  invocation : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  store_authority_cid : String,
  generation_index : Int,
  member_index : Int,
  row : Int,
  input_name : String,
  candidate : @publication.StoredGeneratedContentReference,
  content : @values.CheckedValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  RecoveredClientEffectCommandContent,
  ClientEffectCommandContentIssue,
] {
  if member_index < 0 ||
    row < 0 ||
    max_fields < 0 ||
    max_work < 0 ||
    max_bytes < 0 ||
    max_nodes < 0 ||
    max_depth < 0 {
    return Err(InvalidLimits)
  }
  if client_compiled_effect_program(run, owner) is None ||
    check_client_compiled_run_definition(run, definition) is Err(_) ||
    @publication.effect_preview_program_definition_cid(preview) !=
    prepared_client_effect_computation_definition_cid(owner) ||
    @publication.effect_preview_program_semantics_cid(preview) !=
    prepared_client_effect_computation_semantics_cid(owner) ||
    @publication.effect_preview_check_environment_cid(preview) !=
    prepared_client_effect_computation_environment_cid(owner) {
    return Err(ForeignInput)
  }
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_at(headers, member_index) is Some(header) &&
    @publication.effect_preview_member_effect_id(preview, member_index) ==
    Some(@syntax.effect_header_id(header)) &&
    @publication.effect_preview_member_kind(preview, member_index) ==
    Some("command") &&
    @publication.captured_effect_source_result_from_capture(
      preview, member_index, invocation, source, captured, store_authority_cid, max_bytes,
      max_nodes, max_depth,
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
  guard client_compiled_run_serialization(run) is Some(component) &&
    physical_equal(component.owner, run.owner) else {
    return Err(ForeignInput)
  }
  let generation = match
    @publication.readmit_captured_generated_content_observation(
      captured,
      definition,
      run.template,
      component.output.node_id,
      component.output.logical_cid,
      store_authority_cid,
      generation_index,
      candidate,
      content,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignInput)
  }
  // Reuse the compiler's exact task/step/input-fragment/policy/quantity checks.
  // The expected generation identity came from this CapturedRun, not its caller.
  guard @publication.bound_content_generation_input_artifact(generation)
    is Some(input) &&
    @publication.bound_content_generation_derivation(generation)
    is Some(derivation) &&
    @publication.bound_content_generation_value(generation) is Some(evidence) &&
    readmit_client_serialization_generation_evidence(
      run,
      definition,
      @publication.run_evidence_value_identity(evidence),
      input,
      derivation,
      evidence,
      candidate,
      content,
    )
    is Ok(_) else {
    return Err(ForeignInput)
  }
  let result : RecoveredClientEffectCommandContent = {
    original: Some({
      run,
      owner,
      definition,
      captured,
      preview,
      generation,
      reference,
      member_index,
      row,
      input_name,
    }),
  }
  if !recovered_client_effect_command_content_current(result) {
    return Err(Unavailable)
  }
  Ok(result)
}

///|
pub fn recovered_client_effect_command_content_current(
  value : RecoveredClientEffectCommandContent,
) -> Bool {
  guard value.original is Some(original) else { return false }
  @publication.bound_content_generation_value(original.generation) is Some(_) &&
  @values.reference_available(original.reference) &&
  value.original.map(current => physical_equal(current, original)) == Some(true)
}

///|
/// Compare the retained original occurrence, not equal Run/capture envelopes.
pub fn recovered_client_effect_command_content_matches(
  value : RecoveredClientEffectCommandContent,
  run : ClientCompiledRun,
  owner : PreparedClientEffectComputation,
  definition : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row : Int,
  input_name : String,
) -> Bool {
  guard value.original is Some(original) else { return false }
  physical_equal(original.run, run) &&
  physical_equal(original.owner, owner) &&
  physical_equal(original.definition, definition) &&
  physical_equal(original.captured, captured) &&
  physical_equal(original.preview, preview) &&
  original.member_index == member_index &&
  original.row == row &&
  original.input_name == input_name &&
  recovered_client_effect_command_content_current(value)
}

///|
pub fn recovered_client_effect_command_content_matches_issued(
  value : RecoveredClientEffectCommandContent,
  content : @values.CheckedValue,
) -> Bool {
  guard value.original is Some(original) &&
    content.value is @values.Reference(reference) else {
    return false
  }
  physical_equal(reference, original.reference) &&
  recovered_client_effect_command_content_current(value)
}

///|
pub fn recovered_client_effect_command_content_wire(
  value : RecoveredClientEffectCommandContent,
) -> Result[String, ClientEffectCommandContentIssue] {
  if !recovered_client_effect_command_content_current(value) {
    return Err(Unavailable)
  }
  guard value.original is Some(original) else { return Err(Unavailable) }
  Ok(@values.reference_wire(original.reference))
}

///|
/// Alias release only. Physical readers and Store holdings remain with their
/// original parent; there is deliberately no reconstructed workspace borrower.
pub fn release_recovered_client_effect_command_content(
  value : RecoveredClientEffectCommandContent,
) -> Unit {
  value.original = None
}
