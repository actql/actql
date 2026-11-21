///|
fn date_interval_addition(
  expression : @lower.Expression,
  unit : String,
  date : Value,
  amount : Value,
) -> Result[Value, ScalarIssue] {
  if date is Null || amount is Null {
    return Ok(Null)
  }
  guard unit == "d" &&
    date is Captured(@admitted.Date(_)) &&
    amount is Captured(@admitted.Signed64(days)) &&
    temporal_difference_instant(date) is Some(start) else {
    return Err(InvalidOperand)
  }
  // Every pair of admitted four-digit dates is closer than this bound.
  // Check before scaling the signed64 interval, including min_int64.
  if days < -3660000L || days > 3660000L {
    return Err(ArithmeticFailure)
  }
  guard @admitted.epoch_parts_timestamp(start.seconds + days * 86400L, 0)
    is Some(text) else {
    return Err(ArithmeticFailure)
  }
  date_calendar_result(expression, text[:10].to_owned())
}

///|
fn date_boundary_difference(
  unit : String,
  end : Value,
  start : Value,
) -> Result[Value, ScalarIssue] {
  if end is Null || start is Null {
    return Ok(Null)
  }
  guard unit == "d" &&
    end is Captured(@admitted.Date(_)) &&
    start is Captured(@admitted.Date(_)) else {
    return Err(InvalidOperand)
  }
  // Date inputs are Gregorian midnights, so exact whole days also count
  // calendar-day boundaries in either direction.
  temporal_whole_units(unit, end, start).map(days => {
    capture(@admitted.signed64_value(days))
  })
}

///|
fn date_boundary_truncate(
  expression : @lower.Expression,
  date : Value,
  part : Value,
) -> Result[Value, ScalarIssue] {
  if date is Null || part is Null {
    return Ok(Null)
  }
  guard part is Text("month") &&
    date is Captured(@admitted.Date(text)) &&
    text.length() == 10 else {
    return Err(InvalidOperand)
  }
  date_calendar_result(expression, text[:8].to_owned() + "01")
}

///|
fn date_calendar_result(
  expression : @lower.Expression,
  text : String,
) -> Result[Value, ScalarIssue] {
  let contract = @contract.with_nullability(
    @lower.expression_contract(expression),
    false,
  )
  match @admitted.checked_date_value(text, contract) {
    Some(checked) => Ok(capture(checked.value))
    None => Err(InvalidOperand)
  }
}
