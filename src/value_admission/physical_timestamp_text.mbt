///|
fn physical_timestamp_digits(text : String, start : Int, end : Int) -> Int? {
  let mut result = 0
  for index in start..<end {
    if text[index] < '0' || text[index] > '9' {
      return None
    }
    result = result * 10 + text[index].to_int() - 48
  }
  Some(result)
}

///|
// Physical RFC3339 text conversion, factored from the existing Calendar
// boundary. This does not broaden canonical Timestamp admission. The caller
// retains the original offset spelling separately; never round a nonzero
// sub-millisecond instant or infer an unknown local timezone.
pub fn normalize_timestamp_text(
  text : String,
  max_input_units : Int,
) -> String? {
  if max_input_units <= 0 ||
    text.length() > max_input_units ||
    text.length() < 20 ||
    text.length() > 40 {
    return None
  }
  let zone_start = if text.has_suffix("Z") || text.has_suffix("z") {
    text.length() - 1
  } else {
    text.length() - 6
  }
  if zone_start < 19 {
    return None
  }
  let offset = if zone_start == text.length() - 1 {
    0
  } else {
    if (text[zone_start] != '+' && text[zone_start] != '-') ||
      text[zone_start + 3] != ':' {
      return None
    }
    guard physical_timestamp_digits(text, zone_start + 1, zone_start + 3)
      is Some(hour) &&
      physical_timestamp_digits(text, zone_start + 4, zone_start + 6)
      is Some(minute) &&
      hour <= 23 &&
      minute <= 59 else {
      return None
    }
    // RFC3339 -00:00 is an unknown local offset, not a known UTC instant.
    if text[zone_start] == '-' && hour == 0 && minute == 0 {
      return None
    }
    (hour * 60 + minute) * (if text[zone_start] == '-' { -1 } else { 1 })
  }
  let fraction = if zone_start == 19 {
    "000"
  } else {
    if text[19] != '.' || zone_start == 20 {
      return None
    }
    let mut digits = ""
    for index in 20..<zone_start {
      let unit = text[index]
      if unit < '0' || unit > '9' || (index >= 23 && unit != '0') {
        return None
      }
      if index < 23 {
        digits += text[index:index + 1].to_owned()
      }
    }
    while digits.length() < 3 {
      digits += "0"
    }
    digits
  }
  let local_spelling = text[:10].to_owned() +
    "T" +
    text[11:19].to_owned() +
    "." +
    fraction +
    "Z"
  if text[10] != 'T' && text[10] != 't' {
    return None
  }
  guard timestamp_epoch_milliseconds(local_spelling) is Some(milliseconds) else {
    return None
  }
  epoch_milliseconds_timestamp(milliseconds - offset.to_int64() * 60000L)
}
