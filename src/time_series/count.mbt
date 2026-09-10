///|
fn digits(text : String, start : Int, end : Int) -> Int {
  let mut value = 0
  for i in start..<end {
    value = value * 10 + text[i].to_int() - 48
  }
  value
}

///|
// The endpoint reader already validated this fixed-width UTC spelling. Count
// milliseconds from year 0000, including its leap day; no host timezone API.
fn timestamp_milliseconds(text : String) -> Int64 {
  let year = digits(text, 0, 4)
  let month = digits(text, 5, 7)
  let day = digits(text, 8, 10)
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
    leap_day
  days.to_int64() * 86400000L +
  digits(text, 11, 13).to_int64() * 3600000L +
  digits(text, 14, 16).to_int64() * 60000L +
  digits(text, 17, 19).to_int64() * 1000L +
  digits(text, 20, 23).to_int64()
}

///|
fn known_count(
  start : Endpoint,
  end : Endpoint,
  step : @temporal.Milliseconds,
) -> Int64? {
  guard start is Literal(a) && end is Literal(z) else { return None }
  if a == z {
    return Some(0L)
  }
  guard step is @temporal.Literal(step) else { return None }
  let duration = timestamp_milliseconds(z) - timestamp_milliseconds(a)
  // Valid endpoints span less than 2^49 milliseconds. Avoid duration+step-1:
  // the admitted step can be as large as the maximum safe JSON integer.
  let extra = if duration % step == 0L { 0L } else { 1L }
  Some(duration / step + extra)
}

///|
/// Conditional exact count for admitted literal ranges, without generating rows.
/// None requires bound-value resolution; Some never discharges other obligations.
pub fn known_row_count(value : CheckedSeries) -> Int64? {
  value.row_count
}
