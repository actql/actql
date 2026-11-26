///|
/// Values projected from one admitted Result row under a checked AoA plan.
/// The enclosing captured source still owns row identity and liveness. This
/// value neither combines authored literals nor authorizes an Effect send.
pub struct EffectPlanRow {
  terminal : EffectPlanTerminal
  source_row_index : Int
  priv selector : EffectPlanProjectedSelector
  fields : Array[(String, @json.CanonicalValue)]
}

///|
priv enum EffectPlanProjectedSelector {
  ProjectedEffectScalar(@json.CanonicalValue)
  ProjectedEffectTuple(@json.CanonicalValue)
}

///|
pub(all) enum EffectPlanRowIssue {
  InvalidLimits
  InvalidRow
  WorkLimit
  MissingSelector
  InvalidTupleComponent(String)
  MissingSourceField(String)
} derive(Eq, Debug)

///|
/// The field-only projection borrows canonical row values for every change.
/// The separate typed-literal emitter is outside this construction profile.
pub fn effect_plan_row_field_only_construction_count(
  terminal : EffectPlanTerminal,
  literals : EffectMappingLiterals,
) -> Int? {
  let count = terminal.field_map.length()
  if terminal.checked_changes != count ||
    effect_mapping_literal_count(literals) != 0 {
    return None
  }
  Some(count + effect_plan_selector_width(terminal.selector))
}

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
  let width = effect_plan_selector_width(terminal.selector)
  // Tuple cells are validated, then read again by the measuring and final
  // writers. Each pass borrows from this exact row without a copied key.
  let lookups = terminal.field_map.length().to_int64() +
    (if width == 0 { 1L } else { 3L * width.to_int64() })
  let work = max_work.to_int64()
  if width > max_fields ||
    terminal.field_map.length() > max_fields - width ||
    lookups > work ||
    row_width.to_int64() > (work - lookups) / lookups {
    return Err(WorkLimit)
  }
  let selector = match terminal.selector {
    ScalarEffectSelector(_, name) =>
      match @json.object_field(source_row, name) {
        Some(value) => ProjectedEffectScalar(value)
        None => return Err(MissingSelector)
      }
    TupleEffectSelector(width) => {
      let mut left = work - (row_width.to_int64() + 1L) * lookups
      let binding = effect_plan_result_binding(terminal)
      for index in 0..<width {
        let component = binding.fields[index]
        guard component.role is EffectTupleSelector(target) else {
          return Err(MissingSelector)
        }
        let name = @schema.field_reference_name(component.field)
        guard @json.object_field(source_row, name) is Some(value) else {
          return Err(MissingSelector)
        }
        guard value is @json.String(text) else {
          return Err(InvalidTupleComponent(target))
        }
        if @schema.field_contract(component.field).shape is @contract.Signed64 {
          let cost = 3L * text.length().to_int64()
          if cost > left {
            return Err(WorkLimit)
          }
          left -= cost
          if text.length() > 20 || @scalar.read_decimal_int64(text) is Err(_) {
            return Err(InvalidTupleComponent(target))
          }
        }
      }
      ProjectedEffectTuple(source_row)
    }
  }
  let fields : Array[(String, @json.CanonicalValue)] = []
  for (target, source) in terminal.field_map {
    let value = match @json.object_field(source_row, source) {
      Some(value) => value
      None => return Err(MissingSourceField(source))
    }
    fields.push((target, value))
  }
  Ok({ terminal, source_row_index, selector, fields, })
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
pub fn emit_effect_plan_row_selector(
  row : EffectPlanRow,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match row.selector {
    ProjectedEffectScalar(value) => @json.emit_value(value, writer)
    ProjectedEffectTuple(source_row) => {
      guard row.terminal.selector is TupleEffectSelector(width) else {
        raise @encode.InvalidStructure
      }
      @encode.begin_array(writer)
      let binding = effect_plan_result_binding(row.terminal)
      for index in 0..<width {
        let name = @schema.field_reference_name(binding.fields[index].field)
        @json.emit_value(@json.object_field(source_row, name).unwrap(), writer)
      }
      @encode.end_array(writer)
    }
  }
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
  before_encode? : ((Int, Int, Int) -> Bool)? = None,
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
    if before_encode is Some(fund) {
      let (bytes, nodes, depth) = {
        let measured = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
        defer @encode.cancel_writer(measured)
        emit_effect_plan_row_intended_changes(
          measured,
          terminal.operation,
          changes,
        )
        @encode.finish_measurement_usage(measured)
      }
      if !fund(bytes, nodes, depth) {
        return Err(OutputLimit)
      }
    }
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_effect_plan_row_intended_changes(writer, terminal.operation, changes)
    @encode.finish(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  Ok(output)
}

///|
fn emit_effect_plan_row_intended_changes(
  writer : @encode.Writer,
  operation : String,
  changes : Array[(String, EffectPlanChangeValue)],
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "state")
  @encode.string_value(
    writer,
    if operation == "delete" {
      "not_applicable"
    } else {
      "present"
    },
  )
  if operation != "delete" {
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
}
