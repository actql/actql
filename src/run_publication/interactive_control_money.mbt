///|
pub(all) enum RunControlMoneyIssue {
  InvalidControlAmount
  ControlAmountOverflow
} derive(Eq, Debug)

///|
/// New negotiated amount domain, not a restriction on general mathematical
/// Money. Match the existing ledger's checked nonnegative Int64 aggregation.
pub fn parse_control_amount_micro(
  text : String,
) -> Result[Int64, RunControlMoneyIssue] {
  if text.is_empty() || (text.length() > 1 && text[0] == '0') {
    return Err(InvalidControlAmount)
  }
  let mut amount = 0L
  for char in text.to_array() {
    let digit = char.to_int() - 48
    if digit < 0 || digit > 9 {
      return Err(InvalidControlAmount)
    }
    let digit = digit.to_int64()
    if amount > (9223372036854775807L - digit) / 10L {
      return Err(ControlAmountOverflow)
    }
    amount = amount * 10L + digit
  }
  Ok(amount)
}

///|
/// Exact decimal-unit syntax normalization for facades. It does not authorize
/// a currency, select a tariff/scope, or enable cost guards. No binary float.
pub fn normalize_control_amount_decimal(
  text : String,
) -> Result[String, RunControlMoneyIssue] {
  let parts = text.split(".").to_array()
  if parts.length() < 1 ||
    parts.length() > 2 ||
    (parts.length() == 2 && (parts[1].is_empty() || parts[1].length() > 6)) {
    return Err(InvalidControlAmount)
  }
  let whole = match parse_control_amount_micro(parts[0].to_owned()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut fraction = 0L
  if parts.length() == 2 {
    for char in parts[1].to_array() {
      let digit = char.to_int() - 48
      if digit < 0 || digit > 9 {
        return Err(InvalidControlAmount)
      }
      fraction = fraction * 10L + digit.to_int64()
    }
    for i = parts[1].length(); i < 6; i = i + 1 {
      fraction = fraction * 10L
    }
  }
  if whole > (9223372036854775807L - fraction) / 1000000L {
    return Err(ControlAmountOverflow)
  }
  Ok((whole * 1000000L + fraction).to_string())
}
