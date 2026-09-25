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
  (Int, String, String, String, String, String, String?, String),
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
        ),
      )
    }
  }
  Err(MissingMapping)
}
