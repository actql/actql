///|
fn sql_timestamp_digits(text : String, start : Int, width : Int) -> (Int, Int)? {
  let mut end = start
  let mut value = 0
  while end < text.length() && end - start < width {
    let unit = text[end]
    if unit < '0' || unit > '9' {
      break
    }
    value = value * 10 + unit.to_int() - 48
    end += 1
  }
  if end == start {
    None
  } else {
    Some((value, end))
  }
}

///|
fn sql_timestamp_offset(text : String, start : Int) -> Int? {
  let end = text.length()
  if start == end ||
    (start + 1 == end && (text[start] == 'Z' || text[start] == 'z')) {
    return Some(0)
  }
  if text[start] == ' ' {
    return if text[start:] == " Etc/UTC" || text[start:] == " UTC" {
      Some(0)
    } else {
      None
    }
  }
  let sign = match text[start] {
    '+' => 1
    '-' => -1
    _ => return None
  }
  guard sql_timestamp_digits(text, start + 1, 2) is Some((hour, after_hour)) else {
    return None
  }
  let minute = if after_hour == end {
    0
  } else {
    guard text[after_hour] == ':' &&
      sql_timestamp_digits(text, after_hour + 1, 2)
      is Some((minute, end_of_minutes)) &&
      end_of_minutes == end &&
      minute < 60 else {
      return None
    }
    minute
  }
  let minutes = hour * 60 + minute
  if minutes <= 14 * 60 {
    Some(sign * minutes)
  } else {
    None
  }
}

///|
/// Convert a decoded GoogleSQL literal with an explicit fixed offset or UTC
/// to the canonical Timestamp spelling. Calendar validity and epoch math use
/// the same deterministic Common owner as existing Timestamp Values.
pub fn normalize_sql_timestamp_literal(text : String) -> String? {
  let end = text.length()
  // YYYY-MM-DD + separator + HH:MM:SS + .ffffff + optional " Etc/UTC".
  guard end >= 8 &&
    end <= 34 &&
    text[4] == '-' &&
    timestamp_digits(text, 0, 4) is Some(year) &&
    year > 0 &&
    sql_timestamp_digits(text, 5, 2) is Some((month, month_end)) &&
    month_end < end &&
    text[month_end] == '-' &&
    sql_timestamp_digits(text, month_end + 1, 2) is Some((day, day_end)) else {
    return None
  }
  let (hour, minute, second, time_end) = if day_end == end {
    (0, 0, 0, end)
  } else {
    guard (text[day_end] == ' ' || text[day_end] == 'T' || text[day_end] == 't') &&
      sql_timestamp_digits(text, day_end + 1, 2) is Some((hour, hour_end)) &&
      hour_end < end &&
      text[hour_end] == ':' &&
      sql_timestamp_digits(text, hour_end + 1, 2) is Some((minute, minute_end)) &&
      minute_end < end &&
      text[minute_end] == ':' &&
      sql_timestamp_digits(text, minute_end + 1, 2) is Some((second, time_end)) &&
      second <= 60 else {
      return None
    }
    (hour, minute, second, time_end)
  }
  let (nanoseconds, zone_start) = if time_end < end && text[time_end] == '.' {
    guard sql_timestamp_digits(text, time_end + 1, 6)
      is Some((fraction, fraction_end)) else {
      return None
    }
    let mut nanoseconds = fraction
    for _ in (fraction_end - time_end - 1)..<9 {
      nanoseconds *= 10
    }
    (nanoseconds, fraction_end)
  } else {
    (0, time_end)
  }
  guard sql_timestamp_offset(text, zone_start) is Some(offset) else {
    return None
  }
  // Build the local minute first. Adding the second separately also normalizes
  // 60 to the beginning of the next minute without rounding the fraction.
  let civil_spelling = text[:4].to_owned() +
    "-" +
    timestamp_two_digits(month.to_int64()) +
    "-" +
    timestamp_two_digits(day.to_int64()) +
    "T" +
    timestamp_two_digits(hour.to_int64()) +
    ":" +
    timestamp_two_digits(minute.to_int64()) +
    ":00.000Z"
  guard timestamp_instant(civil_spelling) is Some(instant) &&
    epoch_parts_timestamp(
      instant.seconds + second.to_int64() - offset.to_int64() * 60L,
      nanoseconds,
    )
    is Some(timestamp) &&
    !timestamp.has_prefix("0000-") else {
    return None
  }
  Some(timestamp)
}
