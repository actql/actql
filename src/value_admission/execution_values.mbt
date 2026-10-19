///|
/// Bind a computed null to its exact nullable contract.
pub fn checked_null_value(contract : @contract.Contract) -> CheckedValue? {
  if contract.nullable {
    Some({ contract, value: Null, })
  } else {
    None
  }
}

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
  guard @scalar.admit_utf8_length(value, 2147483647) is Ok(bytes) &&
    text_value(value, bytes) is Some(text) &&
    @scalar.unicode_scalar_count(value) is Some(codepoints) else {
    return None
  }
  let count = codepoints.to_int64()
  let byte_count = bytes.to_int64()
  if (bounds.min_length is Some(limit) && count < limit) ||
    (bounds.max_codepoints is Some(limit) && count > limit) ||
    (bounds.max_utf8_bytes is Some(limit) && byte_count > limit) ||
    !text_enum_accepts(value, bounds) {
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
/// Exact UTC Value projection. Seconds are floored, and nanoseconds are in
/// 0..<1000000000, including before the epoch. This is DATA, not a clock issuer.
pub struct TimestampInstant {
  seconds : Int64
  nanoseconds : Int
} derive(Eq, Debug)

///|
/// Read only canonical UTC Value spelling, without host dates or binary64.
pub fn timestamp_instant(text : String) -> TimestampInstant? {
  let length = text.length()
  if length < 24 ||
    length > 30 ||
    text[4] != '-' ||
    text[7] != '-' ||
    text[10] != 'T' ||
    text[13] != ':' ||
    text[16] != ':' ||
    text[19] != '.' ||
    text[length - 1] != 'Z' ||
    (length > 24 && text[length - 2] == '0') {
    return None
  }
  guard timestamp_digits(text, 0, 4) is Some(year) &&
    timestamp_digits(text, 5, 7) is Some(month) &&
    timestamp_digits(text, 8, 10) is Some(day) &&
    timestamp_digits(text, 11, 13) is Some(hour) &&
    timestamp_digits(text, 14, 16) is Some(minute) &&
    timestamp_digits(text, 17, 19) is Some(second) &&
    timestamp_digits(text, 20, length - 1) is Some(fraction) else {
    return None
  }
  if month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59 {
    return None
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let month_lengths = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if day < 1 || day > month_lengths[month - 1] {
    return None
  }
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
  let mut nanoseconds = fraction
  for _ in (length - 21)..<9 {
    nanoseconds *= 10
  }
  Some({
    seconds: days.to_int64() * 86400L +
    hour.to_int64() * 3600L +
    minute.to_int64() * 60L +
    second.to_int64(),
    nanoseconds,
  })
}

///|
/// Lossless millisecond-only projection, also used by operational clocks.
/// A finer Value is not a trusted sample and must not be truncated here.
pub fn timestamp_epoch_milliseconds(text : String) -> Int64? {
  guard text.length() == 24 && timestamp_instant(text) is Some(instant) else {
    return None
  }
  Some(instant.seconds * 1000L + (instant.nanoseconds / 1000000).to_int64())
}

///|
/// Exact chronological order for canonical UTC Values. The fixed calendar
/// prefix orders chronologically; virtual fractional zeros avoid comparing Z
/// against a finer fractional digit. No replacement Value or CID is issued.
pub fn compare_timestamp_text(left : String, right : String) -> Int? {
  guard timestamp_instant(left) is Some(a) &&
    timestamp_instant(right) is Some(b) else {
    return None
  }
  Some(
    if a.seconds < b.seconds {
      -1
    } else if a.seconds > b.seconds {
      1
    } else if a.nanoseconds < b.nanoseconds {
      -1
    } else if a.nanoseconds > b.nanoseconds {
      1
    } else {
      0
    },
  )
}

///|
/// Internal sort token only; canonical Value serialization keeps its original
/// shortest fractional spelling. The caller retains the admitted Value.
pub fn timestamp_order_text(text : String) -> String? {
  guard timestamp_instant(text) is Some(_) else { return None }
  let mut out = text[:text.length() - 1].to_owned()
  while out.length() < 29 {
    out += "0"
  }
  Some(out + "Z")
}

///|
/// Bind a generated canonical UTC timestamp to its exact non-null contract.
pub fn checked_timestamp_value(
  text : String,
  contract : @contract.Contract,
) -> CheckedValue? {
  guard !contract.nullable &&
    contract.shape is @contract.Timestamp &&
    timestamp_instant(text) is Some(_) else {
    return None
  }
  Some({ contract, value: Timestamp(text), })
}

///|
/// Bind a generated calendar date to its exact non-null Date contract.
pub fn checked_date_value(
  text : String,
  contract : @contract.Contract,
) -> CheckedValue? {
  guard !contract.nullable &&
    contract.shape is @contract.Date &&
    text.length() == 10 &&
    valid_date(text) else {
    return None
  }
  Some({ contract, value: Date(text), })
}

///|
fn timestamp_days_before_year(year : Int64) -> Int64 {
  365L * year + (year + 3L) / 4L - (year + 99L) / 100L + (year + 399L) / 400L
}

///|
fn timestamp_two_digits(value : Int64) -> String {
  if value < 10L {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn timestamp_three_digits(value : Int64) -> String {
  if value < 10L {
    "00" + value.to_string()
  } else if value < 100L {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn timestamp_four_digits(value : Int64) -> String {
  if value < 10L {
    "000" + value.to_string()
  } else if value < 100L {
    "00" + value.to_string()
  } else if value < 1000L {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
/// Convert Unix epoch milliseconds to the canonical UTC millisecond spelling.
/// The supported domain is the same proleptic Gregorian year 0000..9999 range
/// admitted by timestamp values. Host calendar and timezone APIs are not used.
pub fn epoch_milliseconds_timestamp(milliseconds : Int64) -> String? {
  let day_ms = 86400000L
  let mut epoch_day = milliseconds / day_ms
  let mut within_day = milliseconds % day_ms
  if within_day < 0L {
    epoch_day -= 1L
    within_day += day_ms
  }
  let absolute_day = epoch_day + 719528L
  if absolute_day < 0L || absolute_day >= timestamp_days_before_year(10000L) {
    return None
  }
  let mut low = 0L
  let mut high = 10000L
  while low + 1L < high {
    let middle = low + (high - low) / 2L
    if timestamp_days_before_year(middle) <= absolute_day {
      low = middle
    } else {
      high = middle
    }
  }
  let year = low
  let leap = year % 4L == 0L && (year % 100L != 0L || year % 400L == 0L)
  let month_lengths : Array[Int64] = [
    31L,
    if leap {
      29L
    } else {
      28L
    },
    31L,
    30L,
    31L,
    30L,
    31L,
    31L,
    30L,
    31L,
    30L,
    31L,
  ]
  let mut day_in_year = absolute_day - timestamp_days_before_year(year)
  let mut month = 0
  while day_in_year >= month_lengths[month] {
    day_in_year -= month_lengths[month]
    month += 1
  }
  let hour = within_day / 3600000L
  within_day %= 3600000L
  let minute = within_day / 60000L
  within_day %= 60000L
  let second = within_day / 1000L
  let millisecond = within_day % 1000L
  Some(
    timestamp_four_digits(year) +
    "-" +
    timestamp_two_digits(month.to_int64() + 1L) +
    "-" +
    timestamp_two_digits(day_in_year + 1L) +
    "T" +
    timestamp_two_digits(hour) +
    ":" +
    timestamp_two_digits(minute) +
    ":" +
    timestamp_two_digits(second) +
    "." +
    timestamp_three_digits(millisecond) +
    "Z",
  )
}

///|
/// Format an exact instant in the existing canonical UTC Value domain.
/// Arbitrary input is range checked before multiplication; no epoch-nanosecond
/// Int64 or floating point intermediate is used.
pub fn epoch_parts_timestamp(seconds : Int64, nanoseconds : Int) -> String? {
  if seconds < -62167219200L ||
    seconds > 253402300799L ||
    nanoseconds < 0 ||
    nanoseconds >= 1000000000 {
    return None
  }
  guard epoch_milliseconds_timestamp(seconds * 1000L) is Some(base) else {
    return None
  }
  let digits = nanoseconds.to_string()
  let padded = "000000000"[:9 - digits.length()].to_owned() + digits
  let mut length = 9
  while length > 3 && padded[length - 1] == '0' {
    length -= 1
  }
  Some(base[:20].to_owned() + padded[:length].to_owned() + "Z")
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
