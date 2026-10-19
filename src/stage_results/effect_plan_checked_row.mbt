///|
/// Checked values selected by one original Mapping terminal. The enclosing
/// Captured owner must bind the reader to its exact Result export; this pure
/// projection alone establishes neither row custody nor Effect authority.
pub struct EffectPlanCheckedRow {
  terminal : EffectPlanTerminal
  source_row_index : Int
  selector : @value.CheckedValue
  fields : Array[(String, @value.CheckedValue)]
}

///|
pub(all) enum EffectPlanCheckedRowIssue {
  InvalidLimits
  WorkLimit
  FieldLimit
  ForeignLiterals
  IncompleteChanges
  MissingSourceField(String)
  ForeignSourceContract(String)
  InvalidReadUsage
  ValueLimit
  Encoding
} derive(Eq, Debug)

///|
priv struct EffectPlanCheckedRowBudget {
  mut work : Int
  mut nodes : Int
  mut text : Int
  depth : Int
}

///|
fn effect_plan_checked_row_spend(
  budget : EffectPlanCheckedRowBudget,
  amount : Int,
) -> Bool {
  if amount < 0 || amount > budget.work {
    false
  } else {
    budget.work -= amount
    true
  }
}

///|
fn effect_plan_checked_row_read(
  terminal : EffectPlanTerminal,
  name : String,
  read : (String, Int, @value.Limits) -> (@value.CheckedValue, Int, Int, Int)?,
  budget : EffectPlanCheckedRowBudget,
) -> Result[@value.CheckedValue, EffectPlanCheckedRowIssue] {
  let binding = effect_mapping_shape_effect(
    effect_mapping_rule_effect(terminal.rule),
  )
  guard effect_result_binding_result(binding) is Some(result) else {
    return Err(MissingSourceField(name))
  }
  let schema = @results.output_schema(result)
  let comparisons = @schema.field_count(schema)
  let name_bytes = @schema.field_reference_name_bytes(schema)
  if !effect_plan_checked_row_spend(budget, name.length()) ||
    !effect_plan_checked_row_spend(budget, name_bytes) ||
    !effect_plan_checked_row_spend(budget, comparisons) {
    return Err(WorkLimit)
  }
  if comparisons > 0 &&
    (
      name.length() > budget.work / comparisons ||
      name_bytes > budget.work / comparisons - name.length()
    ) {
    return Err(WorkLimit)
  }
  budget.work -= comparisons * (name.length() + name_bytes)
  guard @schema.lookup_reference(schema, name) is Some(field) else {
    return Err(MissingSourceField(name))
  }
  guard read(name, budget.work, {
      max_nodes: budget.nodes,
      max_depth: budget.depth,
      max_text_bytes: budget.text,
    })
    is Some((value, work, nodes, text)) else {
    return Err(MissingSourceField(name))
  }
  if work < 0 ||
    work > budget.work ||
    nodes < 1 ||
    nodes > budget.nodes ||
    text < 0 ||
    text > budget.text ||
    nodes > work ||
    text > work - nodes {
    return Err(InvalidReadUsage)
  }
  // A captured reader preserves the checked Result's actual field Contract.
  // Structural equality or a fresh admission under equal bytes is insufficient.
  if !physical_equal(value.contract, field.contract) {
    return Err(ForeignSourceContract(name))
  }
  budget.work -= work
  budget.nodes -= nodes
  budget.text -= text
  Ok(value)
}

///|
/// Resolve the original selector, mapped fields and admitted InlineSet literals
/// once. The reader reports actual lookup/value usage, deducted from one shared
/// finite ceiling across the complete row. No canonical JSON is re-admitted.
pub fn project_effect_plan_checked_row(
  terminal : EffectPlanTerminal,
  literals : EffectMappingLiterals,
  source_row_index : Int,
  read : (String, Int, @value.Limits) -> (@value.CheckedValue, Int, Int, Int)?,
  max_fields : Int,
  max_work : Int,
  values : @value.Limits,
) -> Result[EffectPlanCheckedRow, EffectPlanCheckedRowIssue] {
  if source_row_index < 0 ||
    max_fields < 0 ||
    max_work < 0 ||
    values.max_nodes < 1 ||
    values.max_depth < 0 ||
    values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let budget : EffectPlanCheckedRowBudget = {
    work: max_work,
    nodes: values.max_nodes,
    text: values.max_text_bytes,
    depth: values.max_depth,
  }
  let rule_count = effect_mapping_rule_count(literals.rules)
  let literal_count = effect_mapping_literal_count(literals)
  if !effect_plan_checked_row_spend(budget, rule_count) ||
    !effect_plan_checked_row_spend(budget, literal_count) ||
    !effect_plan_checked_row_spend(budget, literal_count) ||
    !effect_plan_checked_row_spend(budget, terminal.field_map.length()) ||
    !effect_plan_checked_row_spend(budget, 1) {
    return Err(WorkLimit)
  }
  let mut owns_rule = false
  for index in 0..<rule_count {
    if physical_equal(
        effect_mapping_rule_at(literals.rules, index).unwrap(),
        terminal.rule,
      ) {
      owns_rule = true
    }
  }
  if !owns_rule {
    return Err(ForeignLiterals)
  }
  let mut count = terminal.field_map.length()
  if count > max_fields {
    return Err(FieldLimit)
  }
  let mut longest_name = 1
  for (target, _) in terminal.field_map {
    if !effect_plan_checked_row_spend(budget, target.length()) {
      return Err(WorkLimit)
    }
    longest_name = Int::max(longest_name, target.length())
  }
  for index in 0..<literal_count {
    let literal = effect_mapping_literal_at(literals, index).unwrap()
    if physical_equal(literal.rule, terminal.rule) {
      if literal.origin != InlineSet || literal.value is Omitted {
        return Err(IncompleteChanges)
      }
      if count == max_fields {
        return Err(FieldLimit)
      }
      count += 1
      if !effect_plan_checked_row_spend(budget, literal.target_field.length()) {
        return Err(WorkLimit)
      }
      longest_name = Int::max(longest_name, literal.target_field.length())
    }
  }
  if count != terminal.checked_changes {
    return Err(IncompleteChanges)
  }
  if count > max_fields {
    return Err(FieldLimit)
  }
  if !effect_plan_checked_row_spend(budget, count) {
    return Err(WorkLimit)
  }
  if count > 0 && count > budget.work / count {
    return Err(WorkLimit)
  }
  let comparisons = count * count
  if comparisons > 0 && longest_name > budget.work / comparisons {
    return Err(WorkLimit)
  }
  budget.work -= comparisons * longest_name
  let selector = match
    effect_plan_checked_row_read(
      terminal,
      terminal.selector_field,
      read,
      budget,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fields : Array[(String, @value.CheckedValue)] = []
  for (target, source) in terminal.field_map {
    match effect_plan_checked_row_read(terminal, source, read, budget) {
      Ok(value) => fields.push((target, value))
      Err(issue) => return Err(issue)
    }
  }
  for index in 0..<literal_count {
    let literal = effect_mapping_literal_at(literals, index).unwrap()
    if physical_equal(literal.rule, terminal.rule) {
      guard literal.value is Written(value) else {
        return Err(IncompleteChanges)
      }
      if budget.nodes > budget.work || budget.text > budget.work - budget.nodes {
        return Err(WorkLimit)
      }
      guard @value.recheck_runtime_value_usage(value.value, value.contract, {
          max_nodes: budget.nodes,
          max_depth: budget.depth,
          max_text_bytes: budget.text,
        })
        is Some((_, nodes, text)) else {
        return Err(ValueLimit)
      }
      budget.work -= nodes + text
      budget.nodes -= nodes
      budget.text -= text
      // Keep the original admitted literal, including its nominal identity.
      fields.push((literal.target_field, value))
    }
  }
  fields.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  for index in 1..<fields.length() {
    if fields[index - 1].0 == fields[index].0 {
      return Err(IncompleteChanges)
    }
  }
  Ok({ terminal, source_row_index, selector, fields, })
}

///|
pub fn effect_plan_checked_row_selector(
  row : EffectPlanCheckedRow,
) -> @value.CheckedValue {
  row.selector
}

///|
pub fn effect_plan_checked_row_field_count(row : EffectPlanCheckedRow) -> Int {
  row.fields.length()
}

///|
pub fn effect_plan_checked_row_field_at(
  row : EffectPlanCheckedRow,
  index : Int,
) -> (String, @value.CheckedValue)? {
  row.fields.get(index)
}

///|
pub fn effect_plan_checked_row_changes_wire(
  row : EffectPlanCheckedRow,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPlanCheckedRowIssue] {
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "state")
    @encode.string_value(
      writer,
      if row.terminal.operation == "delete" {
        "not_applicable"
      } else {
        "present"
      },
    )
    if row.terminal.operation != "delete" {
      @encode.key(writer, "value")
      @encode.begin_object(writer)
      for (name, value) in row.fields {
        @encode.key(writer, name)
        @value.emit_checked_wire_value(value, writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}
