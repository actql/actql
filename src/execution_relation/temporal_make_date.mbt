///|
fn make_date(
  expression : @lower.Expression,
  year : Value,
  month : Value,
  day : Value,
) -> Result[Value, ScalarIssue] {
  if year is Null || month is Null || day is Null {
    return Ok(Null)
  }
  guard year is Captured(@admitted.Signed64(y)) &&
    month is Captured(@admitted.Signed64(m)) &&
    day is Captured(@admitted.Signed64(d)) else {
    return Err(InvalidOperand)
  }
  guard @admitted.checked_date_parts_value(
      y,
      m,
      d,
      @contract.with_nullability(@lower.expression_contract(expression), false),
    )
    is Some(result) else {
    return Err(InvalidOperand)
  }
  Ok(capture(result.value))
}
