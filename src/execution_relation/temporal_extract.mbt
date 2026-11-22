///|
fn extract_timestamp(value : Value, part : Value) -> Result[Value, ScalarIssue] {
  if value is Null {
    return Ok(Null)
  }
  guard value is Captured(@admitted.Timestamp(text)) &&
    part is Text(name) &&
    @admitted.timestamp_numeric_part(text, name) is Some(extracted) else {
    return Err(InvalidOperand)
  }
  Ok(capture(@admitted.signed64_value(extracted)))
}
