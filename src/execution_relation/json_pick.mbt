///|
/// Traverse only an already admitted object value. Source strings are never
/// reparsed and missing runtime members cannot be guessed from checked shape.
fn json_pick_value(
  source : Value,
  path : Array[String],
  control : ControlBudget,
) -> Result[Value, RowIssue] {
  if path.is_empty() {
    return Err(InvalidRows)
  }
  let mut current = match source {
    Null => return Ok(Null)
    Captured(value) => value
    Number(_) | Boolean(_) | Text(_) => return Err(InvalidRows)
  }
  for segment in path {
    match current {
      @admitted.Null => return Ok(Null)
      @admitted.Object(fields) => {
        let mut found : @admitted.Value? = None
        for i = 0; i < @admitted.element_count(fields); i = i + 1 {
          guard @admitted.element_at(fields, i) is Some((name, value)) else {
            return Err(InvalidRows)
          }
          if !spend_control(control, 1) || !spend_control_text(control, name) {
            return Err(RowLimit)
          }
          if name == segment {
            found = Some(value)
            break
          }
        }
        guard found is Some(value) else { return Err(InvalidRows) }
        current = value
      }
      @admitted.Number(_)
      | @admitted.Boolean(_)
      | @admitted.Text(_)
      | @admitted.Date(_)
      | @admitted.Timestamp(_)
      | @admitted.Decimal(_)
      | @admitted.Array(_)
      | @admitted.Vector(_)
      | @admitted.Reference(_) => return Err(InvalidRows)
      @admitted.JsonData(_) => return Err(InvalidRows)
    }
  }
  Ok(capture(current))
}
