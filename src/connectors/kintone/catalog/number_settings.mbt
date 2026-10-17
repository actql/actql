///|
pub(all) struct NumberSettingsLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum NumberSettingsIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
} derive(Eq, Debug)

///|
/// Original live General Settings, not display metadata or authorization.
/// The physical Site must bind the request/App and live-versus-preview endpoint.
pub struct AppNumberSettings {
  app_id : String
  revision : String
  digits : Int
  decimal_places : Int
  rounding_mode : String
  response_sha256 : String
}

///|
fn settings_integer(text : String, maximum : Int) -> Int? {
  if !form_digits(text) {
    return None
  }
  let mut value = 0
  for unit in text {
    // All original storage settings fit these small documented bounds. Check
    // before multiply, independent of the source string's supplied length.
    let digit = unit.to_int() - 48
    if value > maximum / 10 || value * 10 + digit > maximum {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
pub fn project_number_settings(
  bytes : Bytes,
  app_id : String,
  limits : NumberSettingsLimits,
) -> Result[AppNumberSettings, NumberSettingsIssue] {
  if limits.max_bytes <= 0 || limits.max_nodes <= 0 || limits.max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes || app_id.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if !form_digits(app_id) {
    return Err(InvalidResponse)
  }
  let source = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  guard @decode.open_object(root) is Ok(root) &&
    form_text(root, "revision") is Some(revision) &&
    form_digits(revision) &&
    @decode.lookup(root, "numberPrecision") is Some(precision) &&
    @decode.open_object(precision) is Ok(precision) &&
    form_text(precision, "digits") is Some(digits_text) &&
    settings_integer(digits_text, 30) is Some(digits) &&
    digits >= 1 &&
    form_text(precision, "decimalPlaces") is Some(places_text) &&
    settings_integer(places_text, 10) is Some(decimal_places) &&
    form_text(precision, "roundingMode") is Some(rounding_mode) &&
    ["HALF_EVEN", "UP", "DOWN"].contains(rounding_mode) else {
    return Err(InvalidResponse)
  }
  Ok({
    app_id,
    revision,
    digits,
    decimal_places,
    rounding_mode,
    response_sha256: @sha.hex(bytes),
  })
}
