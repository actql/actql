///|
pub(all) enum EffectCommandTargetIssueKind {
  InvalidLimits
  WorkLimit
  Contract(@environment.CommandTargetIssue)
  TargetKindMismatch
  MissingStoreMappings
  ForeignEnvironment
  MissingStoreMapping(String)
  StoreTargetMismatch
  StoreContractMismatch
  StoreBinding(@environment.StoreCommandIssue)
} derive(Eq, Debug)

///|
pub struct EffectCommandTargetIssue {
  kind : EffectCommandTargetIssueKind
  stage_index : Int
  effect_id : String
}

///|
pub fn effect_command_target_issue_kind(
  issue : EffectCommandTargetIssue,
) -> EffectCommandTargetIssueKind {
  issue.kind
}

///|
pub fn effect_command_target_issue_stage(
  issue : EffectCommandTargetIssue,
) -> Int {
  issue.stage_index
}

///|
pub fn effect_command_target_issue_effect(
  issue : EffectCommandTargetIssue,
) -> String {
  issue.effect_id
}

///|
pub struct EffectCommandTargetBinding {
  effect : EffectResultBinding
  contract : @environment.CommandTarget
  store_binding : @environment.StoreCommandBinding?
}

///|
pub fn effect_command_target_effect(
  value : EffectCommandTargetBinding,
) -> EffectResultBinding {
  value.effect
}

///|
pub fn effect_command_target_contract(
  value : EffectCommandTargetBinding,
) -> @environment.CommandTarget {
  value.contract
}

///|
/// Retain the original checked pair for installed capture. It is not a
/// ResourceRef, current authorization, or permission to execute the Command.
pub fn effect_command_target_store_binding(
  value : EffectCommandTargetBinding,
) -> @environment.StoreCommandBinding? {
  value.store_binding
}

///|
pub struct EffectCommandTargets {
  effects : EffectResultBindings
  references : @environment.CatalogReferences
  entries : Array[EffectCommandTargetBinding]
  work : Int
}

///|
pub fn effect_command_targets_effects(
  value : EffectCommandTargets,
) -> EffectResultBindings {
  value.effects
}

///|
pub fn effect_command_targets_catalogs(
  value : EffectCommandTargets,
) -> @environment.CatalogContents {
  @environment.reference_contents(value.references)
}

///|
pub fn effect_command_targets_references(
  value : EffectCommandTargets,
) -> @environment.CatalogReferences {
  value.references
}

///|
pub fn effect_command_target_count(value : EffectCommandTargets) -> Int {
  value.entries.length()
}

///|
pub fn effect_command_target_at(
  value : EffectCommandTargets,
  index : Int,
) -> EffectCommandTargetBinding? {
  value.entries.get(index)
}

///|
pub fn effect_command_targets_work(value : EffectCommandTargets) -> Int {
  value.work
}

///|
fn command_target_issue(
  kind : EffectCommandTargetIssueKind,
  header : @syntax.EffectHeader,
) -> EffectCommandTargetIssue {
  {
    kind,
    stage_index: @syntax.effect_header_stage(header),
    effect_id: @syntax.effect_header_id(header),
  }
}

///|
/// Match every Command member's checked Result target kind to one exact
/// identity-checked Connector Catalog command whose role references are
/// closed. Input values, permissions, current authority, and the checked
/// Program's Environment binding remain outstanding obligations.
pub fn bind_effect_command_targets(
  effects : EffectResultBindings,
  references : @environment.CatalogReferences,
  max_work : Int,
  mappings? : @environment.MappingContractShapes? = None,
) -> Result[EffectCommandTargets, EffectCommandTargetIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let mut remaining = max_work
  let entries = []
  let catalogs = @environment.reference_contents(references)
  for index in 0..<effect_result_binding_count(effects) {
    let effect = effect_result_binding_at(effects, index).unwrap()
    let header = effect_result_binding_header(effect)
    if remaining == 0 {
      return Err(command_target_issue(WorkLimit, header))
    }
    remaining -= 1
    if @syntax.effect_header_kind(header) != "command" {
      continue
    }
    if @syntax.effect_header_published_store_target(header)
      is Some((target_ref, mapping_ref)) {
      guard mappings is Some(mappings) else {
        return Err(command_target_issue(MissingStoreMappings, header))
      }
      if !physical_equal(
          @environment.mapping_shape_environment(mappings),
          @environment.contract_registry_environment(
            @environment.catalog_registry(catalogs),
          ),
        ) {
        return Err(command_target_issue(ForeignEnvironment, header))
      }
      // One bounded lookup and the fixed original-reference comparisons. The
      // existing pair owner separately charges its Mapping and Catalog work.
      if remaining == 0 {
        return Err(command_target_issue(WorkLimit, header))
      }
      remaining -= 1
      guard @environment.mapping_shape_for(mappings, mapping_ref)
        is Some(mapping) else {
        return Err(
          command_target_issue(MissingStoreMapping(mapping_ref), header),
        )
      }
      if @environment.mapping_shape_target(mapping) != target_ref {
        return Err(command_target_issue(StoreTargetMismatch, header))
      }
      let pair = match
        @environment.bind_store_command(mapping, catalogs, remaining) {
        Ok(value) => value
        Err(@environment.StoreCommandIssue::WorkLimit) =>
          return Err(command_target_issue(WorkLimit, header))
        Err(issue) =>
          return Err(command_target_issue(StoreBinding(issue), header))
      }
      remaining -= @environment.store_command_work(pair)
      let selected = @environment.store_command_target(pair)
      if @environment.command_target_id(selected) !=
        @syntax.effect_header_contract_ref(header) {
        return Err(command_target_issue(StoreContractMismatch, header))
      }
      entries.push({ effect, contract: selected, store_binding: Some(pair), })
      continue
    }
    let selected = match
      @environment.select_command_target(
        catalogs,
        @syntax.effect_header_contract_ref(header),
        remaining,
      ) {
      Ok(value) => value
      Err(@environment.WorkLimit) =>
        return Err(command_target_issue(WorkLimit, header))
      Err(issue) => return Err(command_target_issue(Contract(issue), header))
    }
    remaining -= @environment.command_target_work(selected)
    let mut target_kind : String? = None
    for field_index in 0..<effect_result_field_binding_count(effect) {
      let field = effect_result_field_binding_at(effect, field_index).unwrap()
      if effect_result_field_binding_role(field) == EffectCommandTarget {
        target_kind = @contract.nonnull_resource_ref_kind(
          @schema.field_contract(effect_result_field_binding_field(field)),
        )
      }
    }
    if target_kind != Some(@environment.command_target_resource_kind(selected)) {
      return Err(command_target_issue(TargetKindMismatch, header))
    }
    entries.push({ effect, contract: selected, store_binding: None, })
  }
  Ok({ effects, references, entries, work: max_work - remaining, })
}
