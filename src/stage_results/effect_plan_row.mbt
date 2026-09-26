///|
/// Values projected from one admitted Result row under a checked AoA plan.
/// The enclosing captured source still owns row identity and liveness. This
/// value neither combines authored literals nor authorizes an Effect send.
pub struct EffectPlanRow {
  terminal : EffectPlanTerminal
  source_row_index : Int
  selector_value : @json.CanonicalValue
  fields : Array[(String, @json.CanonicalValue)]
}

///|
pub(all) enum EffectPlanRowIssue {
  InvalidLimits
  InvalidRow
  WorkLimit
  MissingSelector
  MissingSourceField(String)
} derive(Eq, Debug)

///|
/// Resolve the selector and every mapped value from one immutable Result row.
/// Charge the complete linear-scan bound before looking up any field, so a
/// wide row cannot bypass the shared planning work ceiling.
pub fn project_effect_plan_row(
  terminal : EffectPlanTerminal,
  source_row : @json.CanonicalValue,
  source_row_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[EffectPlanRow, EffectPlanRowIssue] {
  if source_row_index < 0 || max_fields < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @json.object_field_count(source_row) is Some(row_width) else {
    return Err(InvalidRow)
  }
  let lookups = terminal.field_map.length() + 1
  if terminal.field_map.length() > max_fields ||
    lookups > max_work ||
    row_width > (max_work - lookups) / lookups {
    return Err(WorkLimit)
  }
  let selector_value = match
    @json.object_field(source_row, terminal.selector_field) {
    Some(value) => value
    None => return Err(MissingSelector)
  }
  let fields : Array[(String, @json.CanonicalValue)] = []
  for (target, source) in terminal.field_map {
    let value = match @json.object_field(source_row, source) {
      Some(value) => value
      None => return Err(MissingSourceField(source))
    }
    fields.push((target, value))
  }
  Ok({ terminal, source_row_index, selector_value, fields, })
}

///|
pub fn effect_plan_row_terminal(value : EffectPlanRow) -> EffectPlanTerminal {
  value.terminal
}

///|
pub fn effect_plan_row_source_index(value : EffectPlanRow) -> Int {
  value.source_row_index
}

///|
pub fn effect_plan_row_selector(value : EffectPlanRow) -> @json.CanonicalValue {
  value.selector_value
}

///|
pub fn effect_plan_row_field_count(value : EffectPlanRow) -> Int {
  value.fields.length()
}

///|
pub fn effect_plan_row_field_at(
  value : EffectPlanRow,
  index : Int,
) -> (String, @json.CanonicalValue)? {
  value.fields.get(index)
}

///|
priv enum EffectPlanChangeValue {
  Projected(@json.CanonicalValue)
  Admitted(@value.CheckedValue)
}

///|
pub(all) enum EffectPlanChangeIssue {
  InvalidLimits
  ForeignLiterals
  IncompleteChanges
  WorkLimit
  OutputLimit
} derive(Eq, Debug)

///|
/// Combine the checked AoA row projection with the same static rule's admitted
/// literals. This is the proposed change body to compare with the private
/// Preview; it is neither a captured-row proof nor mutation authority.
pub fn effect_plan_row_intended_changes_wire(
  row : EffectPlanRow,
  literals : EffectMappingLiterals,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPlanChangeIssue] {
  if max_fields < 0 ||
    max_work < 0 ||
    max_bytes < 0 ||
    max_nodes < 1 ||
    max_depth < 0 {
    return Err(InvalidLimits)
  }
  let terminal = row.terminal
  let rule_count = effect_mapping_rule_count(literals.rules)
  let literal_count = effect_mapping_literal_count(literals)
  if rule_count > max_work || literal_count > max_work - rule_count {
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
  let changes : Array[(String, EffectPlanChangeValue)] = []
  for (target, value) in row.fields {
    changes.push((target, Projected(value)))
  }
  for index in 0..<literal_count {
    let binding = effect_mapping_literal_at(literals, index).unwrap()
    if physical_equal(binding.rule, terminal.rule) {
      if binding.origin != InlineSet {
        return Err(IncompleteChanges)
      }
      match binding.value {
        Written(value) => changes.push((binding.target_field, Admitted(value)))
        Omitted => return Err(IncompleteChanges)
      }
    }
  }
  let count = changes.length()
  if count != terminal.checked_changes {
    return Err(IncompleteChanges)
  }
  if count > max_fields {
    return Err(WorkLimit)
  }
  if count > max_work - rule_count - literal_count {
    return Err(WorkLimit)
  }
  let remaining = max_work - rule_count - literal_count - count
  if count > 0 && count > remaining / count {
    return Err(WorkLimit)
  }
  changes.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  for index in 1..<count {
    if changes[index - 1].0 == changes[index].0 {
      return Err(IncompleteChanges)
    }
  }
  let output = try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "state")
    @encode.string_value(
      writer,
      if terminal.operation == "delete" {
        "not_applicable"
      } else {
        "present"
      },
    )
    if terminal.operation != "delete" {
      @encode.key(writer, "value")
      @encode.begin_object(writer)
      for (target, value) in changes {
        @encode.key(writer, target)
        match value {
          Projected(value) => @json.emit_value(value, writer)
          Admitted(value) => @value.emit_checked_wire_value(value, writer)
        }
      }
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  Ok(output)
}
