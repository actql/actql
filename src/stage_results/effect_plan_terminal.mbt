///|
/// A checked Mapping member's pure AoA planning terminal. This retains the
/// exact Result and Mapping rule owner; it is not a write or apply permit.
pub struct EffectPlanTerminal {
  rule : EffectMappingRuleBinding
  source_result : String
  entity : String
  operation : String
  selector : String
  selector_field : String
  field_map : Array[(String, String)]
  checked_changes : Int
}

///|
/// A result-backed create's checked row mapping. This is a proposal source,
/// not a Preview, physical payload proof, or apply permit.
pub struct EffectCreateRowTerminal {
  rule : EffectMappingRuleBinding
  source_result : String
  row_fields : @environment.MappingRowFields
}

///|
pub(all) enum EffectPlanTerminalIssue {
  InvalidLimits
  FieldLimit
} derive(Eq, Debug)

///|
pub(all) enum EffectPlanBindingIssue {
  InvalidLimits
  WorkLimit
  InvalidMember
  MissingRule
  Terminal(EffectPlanTerminalIssue)
} derive(Eq, Debug)

///|
/// Select the Plan from one member of the rules' own checked Result inventory.
/// Rule indexes are not authored member indexes: Command members are absent.
/// Both sides of the lookup come from the same checked owner, never from a
/// caller-supplied binding or a separately resolved Result name.
pub fn effect_plan_terminal_for_member(
  rules : EffectMappingRules,
  member_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[EffectPlanTerminal?, EffectPlanBindingIssue] {
  if member_index < 0 || max_fields < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let rule = match
    effect_mapping_rule_for_member(rules, member_index, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  prepare_effect_plan_terminal(rule, max_fields).map_err(issue => {
    Terminal(issue)
  })
}

///|
fn effect_mapping_rule_for_member(
  rules : EffectMappingRules,
  member_index : Int,
  max_work : Int,
) -> Result[EffectMappingRuleBinding, EffectPlanBindingIssue] {
  if member_index < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  guard effect_result_binding_at(
      effect_mapping_shapes_effects(effect_mapping_rules_shapes(rules)),
      member_index,
    )
    is Some(binding) else {
    return Err(InvalidMember)
  }
  if effect_mapping_rule_count(rules) > max_work {
    return Err(WorkLimit)
  }
  let header = effect_result_binding_header(binding)
  for index in 0..<effect_mapping_rule_count(rules) {
    let rule = effect_mapping_rule_at(rules, index).unwrap()
    let rule_header = effect_result_binding_header(
      effect_mapping_shape_effect(effect_mapping_rule_effect(rule)),
    )
    if @syntax.effect_header_stage(rule_header) ==
      @syntax.effect_header_stage(header) &&
      @syntax.effect_header_id(rule_header) == @syntax.effect_header_id(header) {
      return Ok(rule)
    }
  }
  Err(MissingRule)
}

///|
pub fn effect_create_row_terminal_for_member(
  rules : EffectMappingRules,
  member_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[EffectCreateRowTerminal?, EffectPlanBindingIssue] {
  if max_fields < 0 {
    return Err(InvalidLimits)
  }
  let rule = match
    effect_mapping_rule_for_member(rules, member_index, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let header = effect_result_binding_header(
    effect_mapping_shape_effect(effect_mapping_rule_effect(rule)),
  )
  if @syntax.effect_header_kind(header) != "create" {
    return Ok(None)
  }
  guard @syntax.effect_header_source_result(header) is Some(source_result) else {
    return Ok(None)
  }
  guard effect_mapping_rule_row_fields(rule) is Some(row_fields) else {
    return Ok(None)
  }
  if @environment.mapping_row_fields_count(row_fields) > max_fields {
    return Err(Terminal(FieldLimit))
  }
  Ok(Some({ rule, source_result, row_fields, }))
}

///|
pub fn effect_create_row_terminal_source_result(
  value : EffectCreateRowTerminal,
) -> String {
  value.source_result
}

///|
/// Only result-correlated update, upsert and delete have this terminal in
/// ActQL 0.1. All other members stay on their own checked planning path.
pub fn prepare_effect_plan_terminal(
  rule : EffectMappingRuleBinding,
  max_fields : Int,
) -> Result[EffectPlanTerminal?, EffectPlanTerminalIssue] {
  if max_fields < 0 {
    return Err(InvalidLimits)
  }
  let effect = effect_mapping_shape_effect(effect_mapping_rule_effect(rule))
  let header = effect_result_binding_header(effect)
  let kind = @syntax.effect_header_kind(header)
  let source_result = match @syntax.effect_header_source_result(header) {
    Some(value) => value
    None => return Ok(None)
  }
  if kind != "update" && kind != "upsert" && kind != "delete" {
    return Ok(None)
  }
  let body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
  let entity = @decode.text(@decode.lookup(body, "target").unwrap()).unwrap()
  let (selector, selector_field) = if kind == "upsert" {
    (
      "byExternalId",
      @decode.text(@decode.lookup(body, "key").unwrap()).unwrap(),
    )
  } else if @decode.lookup(body, "id") is Some(field) {
    ("byId", @decode.text(field).unwrap())
  } else if @decode.lookup(body, "match") is Some(pair) {
    let match_body = @decode.open_object(pair).unwrap()
    (
      "byId",
      @decode.text(@decode.lookup(match_body, "result_field").unwrap()).unwrap(),
    )
  } else {
    return Ok(None)
  }
  let field_map : Array[(String, String)] = []
  if kind != "delete" {
    let changes = @decode.lookup(body, "set").unwrap()
    let count = @decode.object_length(changes).unwrap()
    if count > max_fields {
      return Err(FieldLimit)
    }
    for index in 0..<count {
      let (target, change) = @decode.field_at(changes, index).unwrap()
      let wrapper = @decode.open_object(change).unwrap()
      if @decode.lookup(wrapper, "field") is Some(field) {
        field_map.push((target, @decode.text(field).unwrap()))
      }
    }
    field_map.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  }
  Ok(
    Some({
      rule,
      source_result,
      entity,
      operation: kind,
      selector,
      selector_field,
      field_map,
      checked_changes: if kind == "delete" {
        0
      } else {
        @decode.object_length(@decode.lookup(body, "set").unwrap()).unwrap()
      },
    }),
  )
}

///|
pub(all) enum EffectPlanInventoryIssue {
  InvalidLimits
  InvalidStage
  WorkLimit
  FieldLimit
  MissingPlan(String)
  ForeignPlan(String)
  OutputLimit
  InvalidEncoding
} derive(Eq, Debug)

///|
pub(all) struct EffectPlanIdentityLimits {
  max_work : Int
  max_fields : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
/// Recompute each correlated member's AoA identity from its checked Mapping
/// owner. Preview-supplied CIDs never serve as the plan's source of truth.
pub fn check_effect_preview_plan_inventory(
  rules : EffectMappingRules,
  stage_index : Int,
  preview : @publication.EffectPreviewIdentity,
  limits : EffectPlanIdentityLimits,
) -> Result[Unit, EffectPlanInventoryIssue] {
  if limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let owner = effect_result_bindings_owner(
    effect_mapping_shapes_effects(effect_mapping_rules_shapes(rules)),
  )
  if stage_index < 0 || stage_at(owner, stage_index) is None {
    return Err(InvalidStage)
  }
  let mut remaining = limits.max_work
  let mut remaining_fields = limits.max_fields
  let mut remaining_bytes = limits.max_bytes
  let mut remaining_nodes = limits.max_nodes
  for rule_index in 0..<effect_mapping_rule_count(rules) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let rule = effect_mapping_rule_at(rules, rule_index).unwrap()
    let header = effect_result_binding_header(
      effect_mapping_shape_effect(effect_mapping_rule_effect(rule)),
    )
    if @syntax.effect_header_stage(header) != stage_index {
      continue
    }
    let terminal = match prepare_effect_plan_terminal(rule, remaining_fields) {
      Ok(Some(value)) => value
      Ok(None) => continue
      Err(_) => return Err(FieldLimit)
    }
    remaining_fields -= terminal.checked_changes
    let id = @syntax.effect_header_id(header)
    let mut found = false
    for index in 0..<@publication.effect_preview_member_count(preview) {
      if remaining == 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      if @publication.effect_preview_member_effect_id(preview, index) !=
        Some(id) {
        continue
      }
      found = true
      let (expected, bytes, nodes) = effect_plan_pipeline_hash_usage(
        terminal,
        remaining_bytes,
        remaining_nodes,
        limits.max_depth,
      ) catch {
        @encode.OutputLimit => return Err(OutputLimit)
        _ => return Err(InvalidEncoding)
      }
      remaining_bytes -= bytes
      remaining_nodes -= nodes
      match @publication.effect_preview_member_plan_cid(preview, index) {
        None => return Err(MissingPlan(id))
        Some(cid) if cid != expected => return Err(ForeignPlan(id))
        Some(_) => ()
      }
      break
    }
    if !found {
      return Err(MissingPlan(id))
    }
  }
  Ok(())
}

///|
pub fn effect_plan_terminal_rule(
  terminal : EffectPlanTerminal,
) -> EffectMappingRuleBinding {
  terminal.rule
}

///|
pub fn effect_plan_terminal_source_result(
  terminal : EffectPlanTerminal,
) -> String {
  terminal.source_result
}

///|
/// The source key is the checked named Result. The enclosing plan binds that
/// source to its exact captured occurrence before this graph can be executed.
pub fn emit_effect_plan_pipeline(
  terminal : EffectPlanTerminal,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let output = if terminal.source_result == "intent" {
    "intent_1"
  } else {
    "intent"
  }
  @encode.begin_object(out)
  @encode.key(out, "output")
  @encode.string_value(out, output)
  @encode.key(out, "sources")
  @encode.begin_object(out)
  @encode.key(out, terminal.source_result)
  @encode.begin_object(out)
  @encode.key(out, "sort")
  @encode.string_value(out, "relation")
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.key(out, "steps")
  @encode.begin_array(out)
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, output)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, terminal.source_result)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "EFFECT.plan")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "entity")
  @encode.string_value(out, terminal.entity)
  if !terminal.field_map.is_empty() {
    @encode.key(out, "field_map")
    @encode.begin_object(out)
    for (target, source) in terminal.field_map {
      @encode.key(out, target)
      @encode.string_value(out, source)
    }
    @encode.end_object(out)
  }
  @encode.key(out, "op")
  @encode.string_value(out, terminal.operation)
  @encode.key(out, "selector")
  @encode.string_value(out, terminal.selector)
  @encode.key(out, "selector_field")
  @encode.string_value(out, terminal.selector_field)
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_array(out)
  @encode.key(out, "version")
  @encode.string_value(out, "aoa-pipeline/0.1")
  @encode.end_object(out)
}

///|
pub fn effect_plan_pipeline_cid(
  terminal : EffectPlanTerminal,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  effect_plan_pipeline_hash_usage(terminal, max_bytes, max_nodes, max_depth).0
}

///|
fn effect_plan_pipeline_hash_usage(
  terminal : EffectPlanTerminal,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (String, Int, Int) raise @encode.EncodeFailure {
  let out = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_effect_plan_pipeline(terminal, out)
  let (hash, bytes, nodes) = @encode.finish_hash_usage(out)
  ("sha256:" + hash, bytes, nodes)
}
