///|
pub(all) enum EffectMappingShapeIssueKind {
  InvalidLimits
  WorkLimit
  MissingMapping
  TargetMismatch
} derive(Eq, Debug)

///|
pub struct EffectMappingShapeIssue {
  kind : EffectMappingShapeIssueKind
  stage_index : Int
  effect_id : String
}

///|
pub fn effect_mapping_shape_issue_kind(
  issue : EffectMappingShapeIssue,
) -> EffectMappingShapeIssueKind {
  issue.kind
}

///|
pub fn effect_mapping_shape_issue_stage(issue : EffectMappingShapeIssue) -> Int {
  issue.stage_index
}

///|
pub fn effect_mapping_shape_issue_effect(
  issue : EffectMappingShapeIssue,
) -> String {
  issue.effect_id
}

///|
pub struct EffectMappingShapeBinding {
  effect : EffectResultBinding
  mapping : @environment.MappingContractShape
}

///|
pub fn effect_mapping_shape_effect(
  binding : EffectMappingShapeBinding,
) -> EffectResultBinding {
  binding.effect
}

///|
pub fn effect_mapping_shape_contract(
  binding : EffectMappingShapeBinding,
) -> @environment.MappingContractShape {
  binding.mapping
}

///|
pub struct EffectMappingShapes {
  effects : EffectResultBindings
  mappings : @environment.MappingContractShapes
  entries : Array[EffectMappingShapeBinding]
  work : Int
}

///|
pub fn effect_mapping_shapes_effects(
  value : EffectMappingShapes,
) -> EffectResultBindings {
  value.effects
}

///|
pub fn effect_mapping_shapes_environment(
  value : EffectMappingShapes,
) -> @environment.MappingContractShapes {
  value.mappings
}

///|
pub fn effect_mapping_shape_count(value : EffectMappingShapes) -> Int {
  value.entries.length()
}

///|
pub fn effect_mapping_shape_at(
  value : EffectMappingShapes,
  index : Int,
) -> EffectMappingShapeBinding? {
  value.entries.get(index)
}

///|
pub fn effect_mapping_shapes_work(value : EffectMappingShapes) -> Int {
  value.work
}

///|
fn effect_mapping_shape_issue(
  kind : EffectMappingShapeIssueKind,
  header : @syntax.EffectHeader,
) -> EffectMappingShapeIssue {
  {
    kind,
    stage_index: @syntax.effect_header_stage(header),
    effect_id: @syntax.effect_header_id(header),
  }
}

///|
/// Bind every authored non-Command Mapping reference and exact target to an
/// identity-checked Mapping body. The caller must still bind this Environment
/// to the checked Program, admit all Mapping semantics, and verify authority.
pub fn bind_effect_mapping_shapes(
  effects : EffectResultBindings,
  mappings : @environment.MappingContractShapes,
  max_work : Int,
) -> Result[EffectMappingShapes, EffectMappingShapeIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let mut work = 0
  let entries : Array[EffectMappingShapeBinding] = []
  for index in 0..<effect_result_binding_count(effects) {
    let effect = effect_result_binding_at(effects, index).unwrap()
    let header = effect_result_binding_header(effect)
    if work >= max_work {
      return Err(effect_mapping_shape_issue(WorkLimit, header))
    }
    work += 1
    let kind = @syntax.effect_header_kind(header)
    if kind == "command" {
      continue
    }
    let mapping = match
      @environment.mapping_shape_for(
        mappings,
        @syntax.effect_header_contract_ref(header),
      ) {
      Some(value) => value
      None => return Err(effect_mapping_shape_issue(MissingMapping, header))
    }
    let body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
    let target = @decode.text(@decode.lookup(body, "target").unwrap()).unwrap()
    if target != @environment.mapping_shape_target(mapping) {
      return Err(effect_mapping_shape_issue(TargetMismatch, header))
    }
    entries.push({ effect, mapping, })
  }
  Ok({ effects, mappings, entries, work, })
}
