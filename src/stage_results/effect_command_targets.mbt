///|
pub(all) enum EffectCommandTargetIssueKind {
  InvalidLimits
  WorkLimit
  Contract(@environment.CommandTargetIssue)
  TargetKindMismatch
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
pub struct EffectCommandTargets {
  effects : EffectResultBindings
  catalogs : @environment.CatalogContents
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
  value.catalogs
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
/// identity-checked Connector Catalog command. This is not full Command
/// Contract admission: input values, permissions, current authority, and the
/// checked Program's Environment binding remain outstanding obligations.
pub fn bind_effect_command_targets(
  effects : EffectResultBindings,
  catalogs : @environment.CatalogContents,
  max_work : Int,
) -> Result[EffectCommandTargets, EffectCommandTargetIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let mut remaining = max_work
  let entries = []
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
    entries.push({ effect, contract: selected, })
  }
  Ok({ effects, catalogs, entries, work: max_work - remaining, })
}
