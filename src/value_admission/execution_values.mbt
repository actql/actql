///|
/// Bind a computed Boolean to its exact non-null Boolean contract.
pub fn checked_boolean_value(
  value : Bool,
  contract : @contract.Contract,
) -> CheckedValue? {
  guard !contract.nullable && contract.shape is @contract.Boolean else {
    return None
  }
  Some({ contract, value: Boolean(value), })
}

///|
/// Bind canonical computed text to its exact non-null text contract.
pub fn checked_text_value(
  value : String,
  contract : @contract.Contract,
) -> CheckedValue? {
  guard !contract.nullable && contract.shape is @contract.Text(bounds) else {
    return None
  }
  let bytes = value.length()
  guard text_value(value, bytes) is Some(text) &&
    @scalar.unicode_scalar_count(value) is Some(codepoints) else {
    return None
  }
  let count = codepoints.to_int64()
  let byte_count = bytes.to_int64()
  if (bounds.min_length is Some(limit) && count < limit) ||
    (bounds.max_codepoints is Some(limit) && count > limit) ||
    (bounds.max_utf8_bytes is Some(limit) && byte_count > limit) {
    None
  } else {
    Some({ contract, value: text, })
  }
}

///|
fn timestamp_digits(text : String, start : Int, end : Int) -> Int? {
  if start < 0 || end < start || end > text.length() {
    return None
  }
  let mut value = 0
  for index in start..<end {
    if text[index] < '0' || text[index] > '9' {
      return None
    }
    value = value * 10 + text[index].to_int() - 48
  }
  Some(value)
}

///|
/// Convert an admitted canonical UTC timestamp to Unix epoch milliseconds.
pub fn timestamp_epoch_milliseconds(text : String) -> Int64? {
  if text.length() != 24 ||
    text[4] != '-' ||
    text[7] != '-' ||
    text[10] != 'T' ||
    text[13] != ':' ||
    text[16] != ':' ||
    text[19] != '.' ||
    text[23] != 'Z' {
    return None
  }
  guard timestamp_digits(text, 0, 4) is Some(year) &&
    timestamp_digits(text, 5, 7) is Some(month) &&
    timestamp_digits(text, 8, 10) is Some(day) &&
    timestamp_digits(text, 11, 13) is Some(hour) &&
    timestamp_digits(text, 14, 16) is Some(minute) &&
    timestamp_digits(text, 17, 19) is Some(second) &&
    timestamp_digits(text, 20, 23) is Some(millisecond) else {
    return None
  }
  if month < 1 ||
    month > 12 ||
    day < 1 ||
    day > 31 ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    millisecond > 999 {
    return None
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let before_month = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
  let leap_day = if leap && month > 2 { 1 } else { 0 }
  let days = 365 * year +
    (year + 3) / 4 -
    (year + 99) / 100 +
    (year + 399) / 400 +
    before_month[month - 1] +
    day -
    1 +
    leap_day -
    719528
  Some(
    days.to_int64() * 86400000L +
    hour.to_int64() * 3600000L +
    minute.to_int64() * 60000L +
    second.to_int64() * 1000L +
    millisecond.to_int64(),
  )
}

///|
/// Read an admitted event clock without inferring its encoding from the value.
pub fn event_time_milliseconds(
  value : CheckedValue,
  timestamp : Bool,
) -> Double? {
  if timestamp {
    guard value.contract.shape is @contract.Timestamp &&
      value.value is Timestamp(text) &&
      timestamp_epoch_milliseconds(text) is Some(milliseconds) else {
      return None
    }
    Some(milliseconds.to_double())
  } else {
    guard value.contract.shape is @contract.Number &&
      value.value is Number(number) &&
      !number.is_nan() &&
      !number.is_inf() else {
      return None
    }
    Some(number)
  }
}
