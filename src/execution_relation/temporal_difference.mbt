///|
// Preserve all three original operands and their leases through left-to-right
// eager evaluation, including the admitted literal unit and NULL operands.
priv struct TemporalArgumentsState {
  expression : @lower.Expression
  operation : @lower.ManyOperator
  children : Array[@lower.Expression]
  values : Array[Value]
  roots : Array[ExpressionRootLease?]
  mut index : Int
}

///|
/// The existing Value owner performs calendar and canonical-text admission.
/// No Host Date, epoch-nanosecond Int64, or binary64 input conversion is used.
fn temporal_difference_instant(value : Value) -> @admitted.TimestampInstant? {
  match value {
    Captured(@admitted.Timestamp(text)) => @admitted.timestamp_instant(text)
    Captured(@admitted.Date(text)) => {
      if text.length() != 10 {
        return None
      }
      @admitted.timestamp_instant(text + "T00:00:00.000Z")
    }
    _ => None
  }
}

///|
fn temporal_difference(
  unit : String,
  left : Value,
  right : Value,
) -> Result[Value, ScalarIssue] {
  if left is Null || right is Null {
    return Ok(Null)
  }
  let dates = left is Captured(@admitted.Date(_)) &&
    right is Captured(@admitted.Date(_))
  let timestamps = left is Captured(@admitted.Timestamp(_)) &&
    right is Captured(@admitted.Timestamp(_))
  if (!dates && !timestamps) || (dates && unit != "d") {
    return Err(InvalidOperand)
  }
  if unit == "us" {
    return Err(InvalidOperand)
  }
  // The admitted four-digit calendar bounds this whole-unit result well below
  // 2^53, including the full-range millisecond difference. Conversion is exact.
  temporal_whole_units(unit, left, right).map(count => Number(count.to_double()))
}

///|
fn timestamp_difference(
  unit : String,
  left : Value,
  right : Value,
) -> Result[Value, ScalarIssue] {
  if left is Null || right is Null {
    return Ok(Null)
  }
  guard left is Captured(@admitted.Timestamp(_)) &&
    right is Captured(@admitted.Timestamp(_)) else {
    return Err(InvalidOperand)
  }
  temporal_whole_units(unit, left, right).map(count => {
    capture(@admitted.signed64_value(count))
  })
}

///|
/// Admitted years 0001 through 9999 fit Int64 even in microseconds.
fn temporal_whole_units(
  unit : String,
  left : Value,
  right : Value,
) -> Result[Int64, ScalarIssue] {
  let divisor = match unit {
    "us" | "ms" | "s" => 1L
    "m" => 60L
    "h" => 3600L
    "d" => 86400L
    _ => return Err(InvalidOperand)
  }
  guard temporal_difference_instant(left) is Some(a) &&
    temporal_difference_instant(right) is Some(b) else {
    return Err(InvalidOperand)
  }
  let mut seconds = a.seconds - b.seconds
  let mut nanos = a.nanoseconds - b.nanoseconds
  if nanos < 0 {
    seconds -= 1L
    nanos += 1000000000
  }
  let count = if unit == "us" || unit == "ms" {
    let nanos_per_unit = if unit == "us" { 1000 } else { 1000000 }
    let units_per_second = (1000000000 / nanos_per_unit).to_int64()
    let floor = seconds * units_per_second + (nanos / nanos_per_unit).to_int64()
    if seconds < 0L && nanos % nanos_per_unit != 0 {
      floor + 1L
    } else {
      floor
    }
  } else {
    let quotient = seconds / divisor
    if seconds < 0L && nanos > 0 && seconds % divisor == 0L {
      quotient + 1L
    } else {
      quotient
    }
  }
  Ok(count)
}
