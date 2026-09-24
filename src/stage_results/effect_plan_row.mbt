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
