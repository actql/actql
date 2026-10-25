///|
/// A bounded optimization proof tied to the original parsed/indexed owner.
/// This is not semantic admission. Ordinary checking remains authoritative.
struct ClosedValuesShape {
  original : @syntax.ParsedProgramInput
  fields : Int
  rows : Int
  cells : Int
  inspection_work : Int
}

///|
fn closed_shape_field(
  node : @decode.Cursor,
  name : String,
  remaining : Ref[Int],
) -> @decode.Cursor? {
  guard @decode.object_length(node) is Some(count) else { return None }
  for index in 0..<count {
    if remaining.val == 0 {
      return None
    }
    remaining.val -= 1
    guard @decode.field_at(node, index) is Some((key, value)) else {
      return None
    }
    if key == name {
      return Some(value)
    }
  }
  None
}

///|
fn closed_shape_keys(
  node : @decode.Cursor,
  names : Array[String],
  remaining : Ref[Int],
) -> Bool {
  if @decode.object_length(node) != Some(names.length()) {
    return false
  }
  for name in names {
    if closed_shape_field(node, name, remaining) is None {
      return false
    }
  }
  true
}

///|
fn closed_shape_text(
  node : @decode.Cursor,
  name : String,
  remaining : Ref[Int],
) -> String? {
  guard closed_shape_field(node, name, remaining) is Some(value) else {
    return None
  }
  match @decode.text(value) {
    Ok(text) if !text.is_empty() => Some(text)
    _ => None
  }
}

///|
/// Only the first explicitly proved constructor shape: one numeric Values,
/// no params/effects/imports, one full-field stage Result and one root alias.
/// Field order agreement is an optimization restriction, not a language rule;
/// a different valid shape must use its funded conservative preparation path.
fn closed_values_shape(
  original : @syntax.ParsedProgramInput,
  max_work : Int,
) -> ClosedValuesShape? {
  if max_work < 0 {
    return None
  }
  let remaining = Ref(max_work)
  let root = @syntax.program_input_cursor(original)
  if !closed_shape_keys(root, ["version", "id", "stages", "results"], remaining) ||
    closed_shape_text(root, "version", remaining) != Some("actql/0.1") ||
    closed_shape_text(root, "id", remaining) is None {
    return None
  }
  guard closed_shape_field(root, "stages", remaining) is Some(stages) &&
    @decode.array_length(stages) == Some(1) &&
    @decode.element_at(stages, 0) is Some(stage) else {
    return None
  }
  if !closed_shape_keys(stage, ["id", "inputs", "steps", "results"], remaining) {
    return None
  }
  guard closed_shape_text(stage, "id", remaining) is Some(stage_id) &&
    closed_shape_field(stage, "inputs", remaining) is Some(inputs) &&
    @decode.object_length(inputs) == Some(0) &&
    closed_shape_field(stage, "steps", remaining) is Some(steps) &&
    @decode.array_length(steps) == Some(1) &&
    @decode.element_at(steps, 0) is Some(step) else {
    return None
  }
  if !closed_shape_keys(step, ["as", "values"], remaining) {
    return None
  }
  guard closed_shape_text(step, "as", remaining) is Some(step_id) &&
    closed_shape_field(step, "values", remaining) is Some(values) else {
    return None
  }
  if !closed_shape_keys(values, ["schema", "rows"], remaining) {
    return None
  }
  guard closed_shape_field(values, "schema", remaining) is Some(schema) &&
    @decode.object_length(schema) is Some(fields) &&
    fields > 0 &&
    closed_shape_field(values, "rows", remaining) is Some(row_values) &&
    @decode.array_length(row_values) is Some(rows) else {
    return None
  }
  if rows > 2147483647 / fields {
    return None
  }
  guard closed_shape_field(stage, "results", remaining) is Some(stage_results) &&
    @decode.object_length(stage_results) == Some(1) &&
    @decode.field_at(stage_results, 0) is Some((result_id, result)) &&
    !result_id.is_empty() else {
    return None
  }
  if !closed_shape_keys(result, ["from", "fields"], remaining) ||
    closed_shape_text(result, "from", remaining) != Some(step_id) {
    return None
  }
  guard closed_shape_field(result, "fields", remaining) is Some(selected) &&
    @decode.array_length(selected) == Some(fields) else {
    return None
  }
  for column in 0..<fields {
    if remaining.val == 0 {
      return None
    }
    remaining.val -= 1
    guard @decode.field_at(schema, column) is Some((name, contract)) &&
      !name.is_empty() &&
      @decode.element_at(selected, column) is Some(selected_name) &&
      @decode.text(selected_name) is Ok(selected_name) &&
      name == selected_name else {
      return None
    }
    if !closed_shape_keys(contract, ["type", "nullable"], remaining) ||
      closed_shape_text(contract, "type", remaining) != Some("number") {
      return None
    }
    guard closed_shape_field(contract, "nullable", remaining) is Some(nullable) &&
      @decode.boolean(nullable) is Ok(false) else {
      return None
    }
  }
  for row in 0..<rows {
    if remaining.val == 0 {
      return None
    }
    remaining.val -= 1
    guard @decode.element_at(row_values, row) is Some(row_value) &&
      @decode.object_length(row_value) == Some(fields) else {
      return None
    }
    for column in 0..<fields {
      if remaining.val == 0 {
        return None
      }
      remaining.val -= 1
      guard @decode.field_at(schema, column) is Some((name, _)) &&
        @decode.field_at(row_value, column) is Some((actual, cell)) &&
        actual == name &&
        @decode.finite_number(cell) is Ok(_) else {
        return None
      }
    }
  }
  guard closed_shape_field(root, "results", remaining) is Some(exports) &&
    @decode.object_length(exports) == Some(1) &&
    @decode.field_at(exports, 0) is Some((export_name, export_)) &&
    !export_name.is_empty() else {
    return None
  }
  if !closed_shape_keys(export_, ["from"], remaining) {
    return None
  }
  guard closed_shape_field(export_, "from", remaining) is Some(from) else {
    return None
  }
  if !closed_shape_keys(from, ["stage", "result"], remaining) ||
    closed_shape_text(from, "stage", remaining) != Some(stage_id) ||
    closed_shape_text(from, "result", remaining) != Some(result_id) {
    return None
  }
  Some({
    original,
    fields,
    rows,
    cells: fields * rows,
    inspection_work: max_work - remaining.val,
  })
}

///|
/// Every fixed object lookup is bounded by its closed-key count (sum 98).
/// A successful early match may consume fewer visits; authored key order does
/// not change this pre-inspection maximum.
/// Each schema field pays nine visits; each row one plus one per numeric cell.
/// This projects only this named inspection, not parser or dispatch work.
fn closed_values_shape_work(fields : Int, rows : Int) -> Int? {
  if fields < 1 || rows < 0 {
    return None
  }
  let f = fields.to_int64()
  let r = rows.to_int64()
  let maximum = 2147483647L
  if f > (maximum - 98L) / 9L {
    return None
  }
  let base = 98L + 9L * f
  if r > (maximum - base) / (1L + f) {
    return None
  }
  Some((base + r * (1L + f)).to_int())
}
