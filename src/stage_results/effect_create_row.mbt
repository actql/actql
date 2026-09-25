///|
priv enum EffectCreateChangeValue {
  Source(@json.CanonicalValue)
  Literal(@value.CheckedValue)
}

///|
pub(all) enum EffectCreateRowIssue {
  InvalidLimits
  InvalidRow
  ForeignLiterals
  WorkLimit
  MissingSourceField(String)
  RejectedNull(String)
  MissingLiteral(String)
  OutputLimit
} derive(Eq, Debug)

///|
/// Project a result-backed create from its checked row mapping and admitted
/// literals. This is a proposed body only; the captured source and Preview
/// still require their own exact binding and admission.
pub fn effect_create_row_intended_changes_wire(
  terminal : EffectCreateRowTerminal,
  literals : EffectMappingLiterals,
  source_row : @json.CanonicalValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectCreateRowIssue] {
  if max_fields < 0 ||
    max_work < 0 ||
    max_bytes < 0 ||
    max_nodes < 1 ||
    max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard @json.object_field_count(source_row) is Some(row_width) else {
    return Err(InvalidRow)
  }
  let fields = terminal.row_fields
  let count = @environment.mapping_row_fields_count(fields)
  let rule_count = effect_mapping_rule_count(literals.rules)
  let literal_count = effect_mapping_literal_count(literals)
  if count > max_fields ||
    rule_count > max_work ||
    literal_count > max_work - rule_count ||
    count > max_work - rule_count - literal_count {
    return Err(WorkLimit)
  }
  let remaining = max_work - rule_count - literal_count - count
  if count > 0 &&
    (
      row_width > remaining / count ||
      literal_count > remaining / count - row_width
    ) {
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
  let changes : Array[(String, EffectCreateChangeValue)] = []
  for index in 0..<count {
    let (target, source) = @environment.mapping_row_fields_source_at(
      fields, index,
    ).unwrap()
    if source is Some(name) {
      let value = match @json.object_field(source_row, name) {
        Some(value) => value
        None => return Err(MissingSourceField(name))
      }
      if value is @json.Null {
        match
          @environment.mapping_row_fields_null_behavior_at(fields, index).unwrap() {
          "reject" => return Err(RejectedNull(target))
          "omit" => continue
          _ => ()
        }
      }
      changes.push((target, Source(value)))
    } else {
      let mut found = false
      for at in 0..<literal_count {
        let binding = effect_mapping_literal_at(literals, at).unwrap()
        if physical_equal(binding.rule, terminal.rule) &&
          binding.target_field == target &&
          binding.origin == ContractRow {
          found = true
          match binding.value {
            Written(value) => changes.push((target, Literal(value)))
            Omitted => ()
          }
        }
      }
      if !found {
        return Err(MissingLiteral(target))
      }
    }
  }
  changes.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  let output = try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "state")
    @encode.string_value(writer, "present")
    @encode.key(writer, "value")
    @encode.begin_object(writer)
    for (target, value) in changes {
      @encode.key(writer, target)
      match value {
        Source(value) => @json.emit_value(value, writer)
        Literal(value) => @value.emit_checked_wire_value(value, writer)
      }
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  Ok(output)
}
