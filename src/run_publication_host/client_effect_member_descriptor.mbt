///|
pub(all) enum ClientEffectMemberDescriptorIssue {
  InvalidMember
  MissingMapping
  WorkLimit
} derive(Debug)

///|
/// Resolve one authored Effect and its selected Mapping from the same checked
/// Program owner. Physical observations and current authority remain separate.
pub fn client_effect_member_descriptor(
  owner : PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  max_work : Int,
) -> Result[
  (Int, String, String, String, String, String, String?, String, String?),
  ClientEffectMemberDescriptorIssue,
] {
  if stage_index < 0 || effect_id.is_empty() || max_work < 1 {
    return Err(InvalidMember)
  }
  let candidate = prepared_client_effect_computation_candidate(owner)
  let headers = @checked.effect_program_static_headers(candidate)
  let mut header_index = -1
  let mut remaining = max_work
  for index in 0..<@syntax.effect_header_count(headers) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) == stage_index &&
      @syntax.effect_header_id(header) == effect_id {
      header_index = index
      break
    }
  }
  if header_index < 0 {
    return Err(InvalidMember)
  }
  let header = @syntax.effect_header_at(headers, header_index).unwrap()
  let effects = @checked.effect_program_static_effects(candidate)
  let shapes = @stage_results.effect_mapping_rules_shapes(
    @stage_results.effect_static_candidate_mapping_rules(effects),
  )
  for index in 0..<@stage_results.effect_mapping_shape_count(shapes) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let shape = @stage_results.effect_mapping_shape_at(shapes, index).unwrap()
    let selected = @stage_results.effect_result_binding_header(
      @stage_results.effect_mapping_shape_effect(shape),
    )
    if @syntax.effect_header_stage(selected) ==
      @syntax.effect_header_stage(header) &&
      @syntax.effect_header_id(selected) == @syntax.effect_header_id(header) {
      let mapping = @stage_results.effect_mapping_shape_contract(shape)
      return Ok(
        (
          header_index,
          @syntax.effect_header_id(header),
          @syntax.effect_header_kind(header),
          @environment.mapping_shape_target(mapping),
          @environment.mapping_shape_reference(mapping),
          @environment.mapping_shape_cid(mapping),
          @syntax.effect_header_source_result(header),
          @syntax.effect_header_failure_policy(header),
          @syntax.effect_header_source_table_input(header),
        ),
      )
    }
  }
  Err(MissingMapping)
}

///|
/// Read Table authoring facts from the same checked Effect owner. Absence
/// means this store has no text Table intent, not that a malformed binding can
/// be ignored. Mapping identity remains checked by the member descriptor.
pub fn client_effect_table_write_binding(
  owner : PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  max_work : Int,
) -> Result[
  (String, String, String?, String?, String, String)?,
  ClientEffectMemberDescriptorIssue,
] {
  if stage_index < 0 || effect_id.is_empty() || max_work < 1 {
    return Err(InvalidMember)
  }
  let headers = @checked.effect_program_static_headers(
    prepared_client_effect_computation_candidate(owner),
  )
  let mut remaining = max_work
  for index in 0..<@syntax.effect_header_count(headers) {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) != stage_index ||
      @syntax.effect_header_id(header) != effect_id {
      continue
    }
    guard @syntax.effect_header_table_write(header) is Some(binding) else {
      return Ok(None)
    }
    if remaining < 8 {
      return Err(WorkLimit)
    }
    // Admission validated this closed object and every required member before
    // producing the owner; this projection does not parse new Host input.
    let body = @decode.open_object(binding).unwrap()
    let intent = @decode.text(@decode.required(body, "intent").unwrap()).unwrap()
    let action = @decode.text(@decode.required(body, "action").unwrap()).unwrap()
    let capability = @decode.text(
      @decode.required(body, "capability_cid").unwrap(),
    ).unwrap()
    let installation = @decode.text(
      @decode.required(body, "installation_binding_cid").unwrap(),
    ).unwrap()
    // A checked CREATE has explicit NULL, not an absent binding member.
    let expected = @decode.lookup(body, "expected_table").unwrap()
    let (uuid, generation) = if action == "replace" {
      let expected = @decode.open_object(expected).unwrap()
      (
        Some(
          @decode.text(@decode.required(expected, "table_uuid").unwrap()).unwrap(),
        ),
        Some(
          @decode.text(@decode.required(expected, "generation_cid").unwrap()).unwrap(),
        ),
      )
    } else {
      (None, None)
    }
    return Ok(
      Some((intent, action, uuid, generation, capability, installation)),
    )
  }
  Err(InvalidMember)
}
