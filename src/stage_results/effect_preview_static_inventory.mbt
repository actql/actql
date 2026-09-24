///|
pub(all) enum EffectPreviewStaticInventoryIssue {
  Inventory(EffectPreviewInventoryIssue)
  WorkLimit
  MissingResolvedContract(String)
  ForeignResolvedContract(String)
  ContractCoverageMismatch
} derive(Eq, Debug)

///|
/// Bind each admitted Preview member to the exact static Mapping or Command
/// contract selected from this checked Program's Environment. This does not
/// establish current authority, captured values, or an apply permit.
pub fn check_effect_preview_static_inventory(
  candidate : EffectStaticCandidate,
  stage_index : Int,
  preview : @publication.EffectPreviewIdentity,
  max_work : Int,
) -> Result[Unit, EffectPreviewStaticInventoryIssue] {
  let results = effect_static_candidate_results(candidate)
  let used = match
    check_effect_preview_checked_inventory_usage(
      results, stage_index, preview, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Inventory(issue))
  }
  let mut remaining = max_work - used
  let mut covered = 0
  let shapes = effect_mapping_rules_shapes(
    effect_static_candidate_mapping_rules(candidate),
  )
  for shape_index in 0..<effect_mapping_shape_count(shapes) {
    if remaining <= 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let binding = effect_mapping_shape_at(shapes, shape_index).unwrap()
    let header = effect_result_binding_header(
      effect_mapping_shape_effect(binding),
    )
    if @syntax.effect_header_stage(header) != stage_index {
      continue
    }
    let id = @syntax.effect_header_id(header)
    let mapping = effect_mapping_shape_contract(binding)
    let mut found = false
    for index in 0..<@publication.effect_preview_member_count(preview) {
      if remaining <= 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      if @publication.effect_preview_member_effect_id(preview, index) !=
        Some(id) {
        continue
      }
      found = true
      covered += 1
      match
        @publication.effect_preview_member_resolved_contract(preview, index) {
        Some(@publication.Mapping(reference, cid)) if reference ==
          @environment.mapping_shape_reference(mapping) &&
          cid == @environment.mapping_shape_cid(mapping) => ()
        _ => return Err(ForeignResolvedContract(id))
      }
      break
    }
    if !found {
      return Err(MissingResolvedContract(id))
    }
  }
  let commands = effect_command_inputs_targets(
    effect_static_candidate_command_inputs(candidate),
  )
  for command_index in 0..<effect_command_target_count(commands) {
    if remaining <= 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let binding = effect_command_target_at(commands, command_index).unwrap()
    let header = effect_result_binding_header(
      effect_command_target_effect(binding),
    )
    if @syntax.effect_header_stage(header) != stage_index {
      continue
    }
    let id = @syntax.effect_header_id(header)
    let target = effect_command_target_contract(binding)
    let expected_cid = @environment.member_cid(
      @environment.command_target_member(target),
    )
    let mut found = false
    for index in 0..<@publication.effect_preview_member_count(preview) {
      if remaining <= 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      if @publication.effect_preview_member_effect_id(preview, index) !=
        Some(id) {
        continue
      }
      found = true
      covered += 1
      match
        @publication.effect_preview_member_resolved_contract(preview, index) {
        Some(@publication.Command(reference, cid)) if reference ==
          @syntax.effect_header_contract_ref(header) &&
          cid == expected_cid => ()
        _ => return Err(ForeignResolvedContract(id))
      }
      break
    }
    if !found {
      return Err(MissingResolvedContract(id))
    }
  }
  if covered != @publication.effect_preview_member_count(preview) {
    return Err(ContractCoverageMismatch)
  }
  Ok(())
}
