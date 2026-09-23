///|
pub(all) enum EffectMappingRuleIssueKind {
  InvalidLimits
  WorkLimit
  InvalidBody
  MissingRequiredField(String)
  MissingResultField(String)
  IncompatibleSourceType(String)
  RowFields(@environment.MappingRowFieldsIssue)
  Conversion(@environment.MappingConversionIssue)
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
  conversions : @environment.MappingConversions
  row_fields : @environment.MappingRowFields?
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
pub fn effect_mapping_rule_conversions(
  value : EffectMappingRuleBinding,
) -> @environment.MappingConversions {
  value.conversions
}

///|
pub fn effect_mapping_rule_row_fields(
  value : EffectMappingRuleBinding,
) -> @environment.MappingRowFields? {
  value.row_fields
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
fn effect_mapping_rule_required(
  mapping : @environment.MappingContractShape,
  fields : Array[String],
  remaining : Ref[Int],
  header : @syntax.EffectHeader,
) -> Result[Unit, EffectMappingRuleIssue] {
  let count = @environment.mapping_shape_required_field_count(mapping)
  if fields.length() > remaining.val || count > remaining.val - fields.length() {
    return Err(effect_mapping_rule_issue(WorkLimit, header))
  }
  remaining.val -= fields.length() + count
  let present : Map[String, Bool] = Map([])
  for field in fields {
    present[field] = true
  }
  for index in 0..<count {
    let field = @environment.mapping_shape_required_field_at(mapping, index).unwrap()
    if !present.contains(field) {
      return Err(effect_mapping_rule_issue(MissingRequiredField(field), header))
    }
  }
  Ok(())
}

///|
fn effect_mapping_rule_sources(
  rows : @environment.MappingRowFields,
  effect : EffectResultBinding,
  mapping : @environment.MappingContractShape,
  remaining : Ref[Int],
  header : @syntax.EffectHeader,
) -> Result[Unit, EffectMappingRuleIssue] {
  let count = @environment.mapping_row_fields_count(rows)
  if count > remaining.val {
    return Err(effect_mapping_rule_issue(WorkLimit, header))
  }
  remaining.val -= count
  let result = match effect_result_binding_result(effect) {
    Some(value) => value
    None => return Err(effect_mapping_rule_issue(InvalidBody, header))
  }
  let schema = @results.output_schema(result)
  for index in 0..<count {
    let (target, source) = @environment.mapping_row_fields_source_at(
      rows, index,
    ).unwrap()
    if source is Some(name) {
      let field = match @schema.lookup_reference(schema, name) {
        Some(value) => value
        None =>
          return Err(
            effect_mapping_rule_issue(MissingResultField(name), header),
          )
      }
      match
        effect_mapping_rule_direct_type(
          target,
          @schema.field_contract(field),
          mapping,
          remaining,
          header,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  Ok(())
}

///|
/// Check the non-null value shape only. Mapping null behavior and registered
/// conversion laws must be admitted before these bindings become executable.
fn effect_mapping_rule_direct_type(
  target : String,
  source : @contract.Contract,
  mapping : @environment.MappingContractShape,
  remaining : Ref[Int],
  header : @syntax.EffectHeader,
) -> Result[Unit, EffectMappingRuleIssue] {
  let field = match
    @schema.lookup_reference(
      @environment.mapping_shape_target_schema(mapping),
      target,
    ) {
    Some(value) => value
    None => return Err(effect_mapping_rule_issue(InvalidBody, header))
  }
  let (compatible, used) = @contract.assignable_usage(
    @contract.with_nullability(source, false),
    @contract.with_nullability(@schema.field_contract(field), false),
    remaining.val,
  ) catch {
    _ => return Err(effect_mapping_rule_issue(WorkLimit, header))
  }
  remaining.val -= used
  if !compatible {
    return Err(
      effect_mapping_rule_issue(IncompatibleSourceType(target), header),
    )
  }
  Ok(())
}

///|
fn effect_mapping_rule_bound_values(
  effect : EffectResultBinding,
  mapping : @environment.MappingContractShape,
  remaining : Ref[Int],
  header : @syntax.EffectHeader,
) -> Result[Unit, EffectMappingRuleIssue] {
  for index in 0..<effect_result_field_binding_count(effect) {
    let binding = effect_result_field_binding_at(effect, index).unwrap()
    if effect_result_field_binding_role(binding) is EffectValue(target) {
      match
        effect_mapping_rule_direct_type(
          target,
          @schema.field_contract(effect_result_field_binding_field(binding)),
          mapping,
          remaining,
          header,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  Ok(())
}

///|
/// Derive the selector and complete write-field set from retained checked
/// Effect headers, check direct source value shapes, then select a static
/// Mapping rule. Literal values, null behavior, conversion laws, current
/// authority and Preview guards remain separate.
pub fn bind_effect_mapping_rules(
  shapes : EffectMappingShapes,
  max_work : Int,
) -> Result[EffectMappingRules, EffectMappingRuleIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let remaining = Ref(max_work)
  let entries : Array[EffectMappingRuleBinding] = []
  let checked_conversions : Map[String, @environment.MappingConversions] = Map([])
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
    let conversions = match
      checked_conversions.get(@environment.mapping_shape_cid(mapping)) {
      Some(value) => value
      None => {
        let admitted = match
          @environment.check_mapping_conversions(mapping, remaining.val) {
          Ok(value) => value
          Err(@environment.WorkLimit) =>
            return Err(effect_mapping_rule_issue(WorkLimit, header))
          Err(issue) =>
            return Err(effect_mapping_rule_issue(Conversion(issue), header))
        }
        remaining.val -= @environment.mapping_conversions_work(admitted)
        checked_conversions[@environment.mapping_shape_cid(mapping)] = admitted
        admitted
      }
    }
    let mut row_fields : @environment.MappingRowFields? = None
    let fields = match kind {
      "update" | "upsert" => {
        let source = @decode.lookup(object, "set").unwrap()
        match effect_mapping_rule_fields(source, remaining, header) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      "delete" => []
      "create" if @decode.lookup(object, "payload") is Some(payload) => {
        let fields = match
          effect_mapping_rule_fields(payload, remaining, header) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        match effect_mapping_rule_required(mapping, fields, remaining, header) {
          Ok(_) => fields
          Err(issue) => return Err(issue)
        }
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
        row_fields = Some(admitted)
        match
          effect_mapping_rule_sources(
            admitted,
            effect_mapping_shape_effect(binding),
            mapping,
            remaining,
            header,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        @environment.mapping_row_fields_names(admitted)
      }
      _ => abort("closed Mapping Effect kind")
    }
    match
      effect_mapping_rule_bound_values(
        effect_mapping_shape_effect(binding),
        mapping,
        remaining,
        header,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
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
    entries.push({
      effect: binding,
      conversions,
      row_fields,
      selection: selected,
    })
  }
  Ok({ shapes, entries, work: max_work - remaining.val, })
}
