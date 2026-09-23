///|
pub(all) struct EffectMappingLiteralLimits {
  max_work : Int
  max_value_nodes : Int
  max_value_depth : Int
  max_value_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum EffectMappingLiteralIssueKind {
  InvalidLimits
  WorkLimit
  IncompatibleLiteral(String)
  RejectedNull(String)
  RequiredOmission(String)
} derive(Eq, Debug)

///|
pub struct EffectMappingLiteralIssue {
  kind : EffectMappingLiteralIssueKind
  stage_index : Int
  effect_id : String
}

///|
pub fn effect_mapping_literal_issue_kind(
  value : EffectMappingLiteralIssue,
) -> EffectMappingLiteralIssueKind {
  value.kind
}

///|
pub fn effect_mapping_literal_issue_stage(
  value : EffectMappingLiteralIssue,
) -> Int {
  value.stage_index
}

///|
pub fn effect_mapping_literal_issue_effect(
  value : EffectMappingLiteralIssue,
) -> String {
  value.effect_id
}

///|
pub(all) enum EffectMappingLiteralOrigin {
  InlineCreate
  InlineSet
  ContractRow
} derive(Eq, Debug)

///|
pub(all) enum EffectMappingLiteralValue {
  Written(@value.CheckedValue)
  Omitted
}

///|
pub struct EffectMappingLiteralBinding {
  rule : EffectMappingRuleBinding
  target_field : String
  origin : EffectMappingLiteralOrigin
  value : EffectMappingLiteralValue
}

///|
pub fn effect_mapping_literal_rule(
  value : EffectMappingLiteralBinding,
) -> EffectMappingRuleBinding {
  value.rule
}

///|
pub fn effect_mapping_literal_target(
  value : EffectMappingLiteralBinding,
) -> String {
  value.target_field
}

///|
pub fn effect_mapping_literal_origin(
  value : EffectMappingLiteralBinding,
) -> EffectMappingLiteralOrigin {
  value.origin
}

///|
pub fn effect_mapping_literal_value(
  value : EffectMappingLiteralBinding,
) -> EffectMappingLiteralValue {
  value.value
}

///|
pub struct EffectMappingLiterals {
  rules : EffectMappingRules
  entries : Array[EffectMappingLiteralBinding]
  used_work : Int
  used_value_nodes : Int
  used_value_text_bytes : Int
}

///|
pub fn effect_mapping_literals_rules(
  value : EffectMappingLiterals,
) -> EffectMappingRules {
  value.rules
}

///|
pub fn effect_mapping_literal_count(value : EffectMappingLiterals) -> Int {
  value.entries.length()
}

///|
pub fn effect_mapping_literal_at(
  value : EffectMappingLiterals,
  index : Int,
) -> EffectMappingLiteralBinding? {
  value.entries.get(index)
}

///|
pub fn effect_mapping_literals_usage(
  value : EffectMappingLiterals,
) -> (Int, Int, Int) {
  (value.used_work, value.used_value_nodes, value.used_value_text_bytes)
}

///|
fn effect_mapping_literal_issue(
  kind : EffectMappingLiteralIssueKind,
  header : @syntax.EffectHeader,
) -> EffectMappingLiteralIssue {
  {
    kind,
    stage_index: @syntax.effect_header_stage(header),
    effect_id: @syntax.effect_header_id(header),
  }
}

///|
fn effect_mapping_literal_admit(
  rule : EffectMappingRuleBinding,
  target : String,
  cursor : @decode.Cursor,
  origin : EffectMappingLiteralOrigin,
  null_behavior : String?,
  limits : EffectMappingLiteralLimits,
  work : Ref[Int],
  nodes : Ref[Int],
  text : Ref[Int],
) -> Result[EffectMappingLiteralBinding, EffectMappingLiteralIssue] {
  let header = effect_result_binding_header(
    effect_mapping_shape_effect(effect_mapping_rule_effect(rule)),
  )
  if work.val == 0 {
    return Err(effect_mapping_literal_issue(WorkLimit, header))
  }
  work.val -= 1
  let mapping = effect_mapping_shape_contract(effect_mapping_rule_effect(rule))
  let field = match
    @schema.lookup_reference(
      @environment.mapping_shape_target_schema(mapping),
      target,
    ) {
    Some(value) => value
    None =>
      return Err(
        effect_mapping_literal_issue(IncompatibleLiteral(target), header),
      )
  }
  if @decode.is_null(cursor) {
    if null_behavior == Some("reject") {
      return Err(effect_mapping_literal_issue(RejectedNull(target), header))
    }
    if null_behavior == Some("omit") {
      let count = @environment.mapping_shape_required_field_count(mapping)
      if count > work.val {
        return Err(effect_mapping_literal_issue(WorkLimit, header))
      }
      work.val -= count
      for index in 0..<count {
        let name = @environment.mapping_shape_required_field_at(mapping, index).unwrap()
        if name == target {
          return Err(
            effect_mapping_literal_issue(RequiredOmission(target), header),
          )
        }
      }
      return Ok({ rule, target_field: target, origin, value: Omitted, })
    }
  }
  let (checked, used_nodes, used_text) = match
    @value.admit_usage(@schema.field_contract(field), cursor, {
      max_nodes: nodes.val,
      max_depth: limits.max_value_depth,
      max_text_bytes: text.val,
    }) {
    Ok(value) => value
    Err(@value.ValueIssue(@value.BudgetExceeded, ..)) =>
      return Err(effect_mapping_literal_issue(WorkLimit, header))
    Err(_) =>
      return Err(
        effect_mapping_literal_issue(IncompatibleLiteral(target), header),
      )
  }
  nodes.val -= used_nodes
  text.val -= used_text
  Ok({ rule, target_field: target, origin, value: Written(checked), })
}

///|
/// Admit every authored or Mapping-owned literal under aggregate value limits.
/// This retains typed values but does not authorize a write or close Preview.
pub fn admit_effect_mapping_literals(
  rules : EffectMappingRules,
  limits : EffectMappingLiteralLimits,
) -> Result[EffectMappingLiterals, EffectMappingLiteralIssue] {
  if limits.max_work < 0 ||
    limits.max_value_nodes < 0 ||
    limits.max_value_depth < 0 ||
    limits.max_value_text_bytes < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let work = Ref(limits.max_work)
  let nodes = Ref(limits.max_value_nodes)
  let text = Ref(limits.max_value_text_bytes)
  let entries : Array[EffectMappingLiteralBinding] = []
  for index in 0..<effect_mapping_rule_count(rules) {
    let rule = effect_mapping_rule_at(rules, index).unwrap()
    let header = effect_result_binding_header(
      effect_mapping_shape_effect(effect_mapping_rule_effect(rule)),
    )
    if work.val == 0 {
      return Err(effect_mapping_literal_issue(WorkLimit, header))
    }
    work.val -= 1
    let body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
    let kind = @syntax.effect_header_kind(header)
    if kind == "create" && @decode.lookup(body, "payload") is Some(payload) {
      let count = @decode.object_length(payload).unwrap()
      for item in 0..<count {
        let (target, cursor) = @decode.field_at(payload, item).unwrap()
        let admitted = match
          effect_mapping_literal_admit(
            rule,
            target,
            cursor,
            InlineCreate,
            None,
            limits,
            work,
            nodes,
            text,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        entries.push(admitted)
      }
    } else if kind == "update" || kind == "upsert" {
      let set = @decode.lookup(body, "set").unwrap()
      let count = @decode.object_length(set).unwrap()
      if count > work.val {
        return Err(effect_mapping_literal_issue(WorkLimit, header))
      }
      work.val -= count
      for item in 0..<count {
        let (target, source) = @decode.field_at(set, item).unwrap()
        let wrapper = @decode.open_object(source).unwrap()
        if @decode.lookup(wrapper, "literal") is Some(cursor) {
          let admitted = match
            effect_mapping_literal_admit(
              rule,
              target,
              cursor,
              InlineSet,
              None,
              limits,
              work,
              nodes,
              text,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          entries.push(admitted)
        }
      }
    } else if kind == "create" || kind == "store" {
      let rows = effect_mapping_rule_row_fields(rule).unwrap()
      let count = @environment.mapping_row_fields_count(rows)
      if count > work.val {
        return Err(effect_mapping_literal_issue(WorkLimit, header))
      }
      work.val -= count
      for item in 0..<count {
        if @environment.mapping_row_fields_literal_at(rows, item)
          is Some(cursor) {
          let (target, _) = @environment.mapping_row_fields_source_at(
            rows, item,
          ).unwrap()
          let behavior = @environment.mapping_row_fields_null_behavior_at(
            rows, item,
          )
          let admitted = match
            effect_mapping_literal_admit(
              rule,
              target,
              cursor,
              ContractRow,
              behavior,
              limits,
              work,
              nodes,
              text,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          entries.push(admitted)
        }
      }
    }
  }
  Ok({
    rules,
    entries,
    used_work: limits.max_work - work.val,
    used_value_nodes: limits.max_value_nodes - nodes.val,
    used_value_text_bytes: limits.max_value_text_bytes - text.val,
  })
}
