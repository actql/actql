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
  Some(count_range(a, z, step))
}

///|
fn count_range(a : String, z : String, step : Int64) -> Int64 {
  let start = @value.timestamp_instant(a).unwrap()
  let end = @value.timestamp_instant(z).unwrap()
  let mut seconds = end.seconds - start.seconds
  let mut nanoseconds = end.nanoseconds - start.nanoseconds
  if nanoseconds < 0 {
    seconds -= 1L
    nanoseconds += 1000000000
  }
  // Admitted, ordered endpoints span less than 2^49 whole milliseconds.
  // Retain the fractional remainder instead of truncating it or overflowing
  // an epoch-nanosecond/duration+step-1 intermediate over the full year domain.
  let milliseconds = seconds * 1000L + (nanoseconds / 1000000).to_int64()
  let extra = if milliseconds % step == 0L && nanoseconds % 1000000 == 0 {
    0L
  } else {
    1L
  }
  milliseconds / step + extra
}

///|
/// Conditional exact count for admitted literal ranges, without generating rows.
/// None requires bound-value resolution; Some never discharges other obligations.
pub fn known_row_count(value : CheckedSeries) -> Int64? {
  value.row_count
}

///|
pub(all) enum CountIssue {
  MissingEndpoint(String)
  InvalidEndpoint(String)
  UnexpectedEndpoint(String)
  MissingStep
  InvalidStep
  UnexpectedStep
  ReversedRange
} derive(Eq, Debug)

///|
fn resolved_endpoint(
  endpoint : Endpoint,
  value : @value.CheckedValue?,
  name : String,
) -> Result[String, CountIssue] {
  match endpoint {
    Literal(text) =>
      if value is None {
        Ok(text)
      } else {
        Err(UnexpectedEndpoint(name))
      }
    Parameter(_) =>
      match value {
        None => Err(MissingEndpoint(name))
        Some(value) =>
          match value.value {
            @value.Timestamp(text) => Ok(text)
            _ => Err(InvalidEndpoint(name))
          }
      }
  }
}

///|
/// Count admitted literal or supplied typed endpoints without materializing rows.
/// The caller owns Parameter-name/owner binding and retains other obligations.
pub fn resolve_row_count(
  series : CheckedSeries,
  start_value? : @value.CheckedValue? = None,
  end_value? : @value.CheckedValue? = None,
  step_value? : Int64? = None,
) -> Result[Int64, CountIssue] {
  let a = match resolved_endpoint(series.start, start_value, "start") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let z = match resolved_endpoint(series.end, end_value, "end") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let step = match (series.step, step_value) {
    (@temporal.Literal(n), None) => n
    (@temporal.Literal(_), Some(_)) => return Err(UnexpectedStep)
    (@temporal.Parameter(_, ..), Some(n)) => n
    (@temporal.Parameter(_, ..), None) => return Err(MissingStep)
  }
  if step <= 0L || step > 9007199254740991L {
    return Err(InvalidStep)
  }
  if @value.compare_timestamp_text(a, z) == Some(1) {
    return Err(ReversedRange)
  }
  Ok(count_range(a, z, step))
}
