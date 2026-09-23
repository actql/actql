///|
pub(all) enum EffectMappingRuleIssueKind {
  InvalidLimits
  WorkLimit
  InvalidBody
  RowFields(@environment.MappingRowFieldsIssue)
  Permission(@environment.MappingPermissionIssue)
} derive(Eq, Debug)

///|
pub struct EffectMappingRuleIssue {
  kind : EffectMappingRuleIssueKind
  stage_index : Int
  effect_id : String
}

///|
pub fn effect_mapping_rule_issue_kind(
  issue : EffectMappingRuleIssue,
) -> EffectMappingRuleIssueKind {
  issue.kind
}

///|
pub fn effect_mapping_rule_issue_stage(issue : EffectMappingRuleIssue) -> Int {
  issue.stage_index
}

///|
pub fn effect_mapping_rule_issue_effect(
  issue : EffectMappingRuleIssue,
) -> String {
  issue.effect_id
}

///|
pub struct EffectMappingRuleBinding {
  effect : EffectMappingShapeBinding
  selection : @environment.MappingPermissionSelection
}

///|
pub fn effect_mapping_rule_effect(
  value : EffectMappingRuleBinding,
) -> EffectMappingShapeBinding {
  value.effect
}

///|
pub fn effect_mapping_rule_selection(
  value : EffectMappingRuleBinding,
) -> @environment.MappingPermissionSelection {
  value.selection
}

///|
pub struct EffectMappingRules {
  shapes : EffectMappingShapes
  entries : Array[EffectMappingRuleBinding]
  work : Int
}

///|
pub fn effect_mapping_rules_shapes(
  value : EffectMappingRules,
) -> EffectMappingShapes {
  value.shapes
}

///|
pub fn effect_mapping_rule_count(value : EffectMappingRules) -> Int {
  value.entries.length()
}

///|
pub fn effect_mapping_rule_at(
  value : EffectMappingRules,
  index : Int,
) -> EffectMappingRuleBinding? {
  value.entries.get(index)
}

///|
pub fn effect_mapping_rules_work(value : EffectMappingRules) -> Int {
  value.work
}

///|
fn effect_mapping_rule_issue(
  kind : EffectMappingRuleIssueKind,
  header : @syntax.EffectHeader,
) -> EffectMappingRuleIssue {
  {
    kind,
    stage_index: @syntax.effect_header_stage(header),
    effect_id: @syntax.effect_header_id(header),
  }
}

///|
fn effect_mapping_rule_fields(
  source : @decode.Cursor,
  remaining : Ref[Int],
  header : @syntax.EffectHeader,
) -> Result[Array[String], EffectMappingRuleIssue] {
  let count = match @decode.object_length(source) {
    Some(value) => value
    None => return Err(effect_mapping_rule_issue(InvalidBody, header))
  }
  if count > remaining.val {
    return Err(effect_mapping_rule_issue(WorkLimit, header))
  }
  remaining.val -= count
  let fields : Array[String] = []
  for index in 0..<count {
    let (field, _) = @decode.field_at(source, index).unwrap()
    fields.push(field)
  }
  Ok(fields)
}

///|
/// Derive the selector and complete write-field set from retained checked
/// Effect headers, then select a static Mapping rule. Result-field values,
/// conversion laws, current authority and Preview guards remain separate.
pub fn bind_effect_mapping_rules(
  shapes : EffectMappingShapes,
  max_work : Int,
) -> Result[EffectMappingRules, EffectMappingRuleIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let remaining = Ref(max_work)
  let entries : Array[EffectMappingRuleBinding] = []
  for index in 0..<effect_mapping_shape_count(shapes) {
    let binding = effect_mapping_shape_at(shapes, index).unwrap()
    let header = effect_result_binding_header(
      effect_mapping_shape_effect(binding),
    )
    if remaining.val == 0 {
      return Err(effect_mapping_rule_issue(WorkLimit, header))
    }
    remaining.val -= 1
    let kind = @syntax.effect_header_kind(header)
    let body = @syntax.effect_header_body(header)
    let object = @decode.open_object(body).unwrap()
    let selector = match kind {
      "update" | "delete" => {
        let mut selected = ""
        for candidate in ["id", "match", "ids", "external_id", "where"] {
          if @decode.lookup(object, candidate) is Some(_) {
            selected = candidate
          }
        }
        if selected.is_empty() {
          return Err(effect_mapping_rule_issue(InvalidBody, header))
        }
        selected
      }
      "upsert" => "key"
      "create" | "store" => "none"
      _ => return Err(effect_mapping_rule_issue(InvalidBody, header))
    }
    let mapping = effect_mapping_shape_contract(binding)
    let fields = match kind {
      "update" | "upsert" => {
        let source = @decode.lookup(object, "set").unwrap()
        match effect_mapping_rule_fields(source, remaining, header) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      "delete" => []
      "create" if @decode.lookup(object, "payload") is Some(payload) =>
        match effect_mapping_rule_fields(payload, remaining, header) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      "create" | "store" => {
        let admitted = match
          @environment.check_mapping_row_fields(mapping, remaining.val) {
          Ok(value) => value
          Err(@environment.WorkLimit) =>
            return Err(effect_mapping_rule_issue(WorkLimit, header))
          Err(issue) =>
            return Err(effect_mapping_rule_issue(RowFields(issue), header))
        }
        remaining.val -= @environment.mapping_row_fields_work(admitted)
        @environment.mapping_row_fields_names(admitted)
      }
      _ => abort("closed Mapping Effect kind")
    }
    let selected = match
      @environment.select_mapping_permissions(
        mapping,
        kind,
        selector,
        fields,
        remaining.val,
      ) {
      Ok(value) => value
      Err(@environment.WorkLimit) =>
        return Err(effect_mapping_rule_issue(WorkLimit, header))
      Err(issue) =>
        return Err(effect_mapping_rule_issue(Permission(issue), header))
    }
    remaining.val -= @environment.mapping_permission_work(selected)
    entries.push({ effect: binding, selection: selected, })
  }
  Ok({ shapes, entries, work: max_work - remaining.val, })
}
