///|
pub(all) enum EffectCommandRowIssue {
  InvalidLimits
  InvalidRow
  WorkLimit
  MissingTarget
  MissingSourceField(String)
  OutputLimit
} derive(Eq, Debug)

///|
/// Resolve a Command through the same admitted member inventory, not by a
/// caller-authored contract name. Non-Command members keep their Mapping path.
pub fn effect_command_input_for_member(
  inputs : EffectCommandInputs,
  member_index : Int,
  max_work : Int,
) -> Result[EffectCommandInputBinding?, EffectPlanBindingIssue] {
  if member_index < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  guard effect_result_binding_at(inputs.targets.effects, member_index)
    is Some(effect) else {
    return Err(InvalidMember)
  }
  if max_work < 1 || inputs.entries.length() > max_work - 1 {
    return Err(WorkLimit)
  }
  if @syntax.effect_header_kind(effect.header) != "command" {
    return Ok(None)
  }
  for input in inputs.entries {
    if physical_equal(input.target.effect, effect) {
      return Ok(Some(input))
    }
  }
  Err(MissingRule)
}

///|
priv enum CommandRowValue {
  Projected(@json.CanonicalValue)
  Admitted(@value.CheckedValue)
}

///|
/// Project exact target and input values from a verified Result export under
/// the checked Command binding. This is neither reference issuance nor send
/// authority: the captured owner must supply provenance and bind the Preview.
/// Charge the complete field-scan and ordering bound before projecting a row.
pub fn project_effect_command_row(
  binding : EffectCommandInputBinding,
  source_row : @json.CanonicalValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String), EffectCommandRowIssue] {
  if max_fields < 0 ||
    max_work < 0 ||
    max_bytes < 0 ||
    max_nodes < 1 ||
    max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard @json.object_field_count(source_row) is Some(width) else {
    return Err(InvalidRow)
  }
  let fields = binding.fields
  let source_fields = binding.target.effect.fields
  // One target lookup plus at most one source lookup for every input field.
  if fields.length() > max_fields || source_fields.length() > max_work {
    return Err(WorkLimit)
  }
  let remaining = max_work - source_fields.length()
  if fields.length() >= remaining {
    return Err(WorkLimit)
  }
  let lookups = fields.length() + 1
  if width > (remaining - lookups) / lookups {
    return Err(WorkLimit)
  }
  let ordering_work = remaining - lookups - width * lookups
  if !fields.is_empty() && fields.length() > ordering_work / fields.length() {
    return Err(WorkLimit)
  }
  let mut target : @json.CanonicalValue? = None
  for source in source_fields {
    if source.role == EffectCommandTarget {
      target = @json.object_field(
        source_row,
        @schema.field_reference_name(source.field),
      )
    }
  }
  guard target is Some(target) else { return Err(MissingTarget) }
  if target is @json.Null {
    return Err(MissingTarget)
  }
  let values : Array[(String, CommandRowValue)] = []
  for field in fields {
    let value : CommandRowValue = match field.value {
      ResultField(source) => {
        let name = @schema.field_reference_name(source)
        guard @json.object_field(source_row, name) is Some(value) else {
          return Err(MissingSourceField(name))
        }
        Projected(value)
      }
      Literal(value) => Admitted(value)
    }
    values.push((field.name, value))
  }
  values.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  try {
    let target_wire = @json.stringify_value(
      target, max_bytes, max_nodes, max_depth,
    )
    let out = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(out)
    @encode.key(out, "state")
    @encode.string_value(out, "present")
    @encode.key(out, "value")
    @encode.begin_object(out)
    for (name, value) in values {
      @encode.key(out, name)
      match value {
        Projected(value) => @json.emit_value(value, out)
        Admitted(value) => @value.emit_checked_wire_value(value, out)
      }
    }
    @encode.end_object(out)
    @encode.end_object(out)
    Ok((target_wire, @encode.finish(out)))
  } catch {
    _ => Err(OutputLimit)
  }
}
