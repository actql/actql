///|
// Fixed structural scratch entries, not physical heap bytes or a capacity grant.
// The coarse calendar-width guard bounds the significand/unit product below
// 100 bits. Binary exponents are checked before shifts; tiny fractions fail
// without allocating a denominator or iterating over their magnitude.
const DATE_ADDITION_SLOTS : Int = 32

///|
fn temporal_duration_parts(amount : Double, unit : String) -> (Int64, Int)? {
  if amount.is_nan() || amount.is_inf() {
    return None
  }
  let negative = amount < 0.0
  let magnitude = if negative { -amount } else { amount }
  // Every valid difference within years 0000..9999 is smaller even in ms.
  // This deliberately loose guard is not a new admitted amount restriction:
  // larger amounts cannot produce a result in the existing calendar range.
  if magnitude > 316000000000000.0 {
    return None
  }
  let nanos_per_unit = match unit {
    "ms" => 1000000L
    "s" => 1000000000L
    "m" => 60000000000L
    "h" => 3600000000000L
    "d" => 86400000000000L
    _ => return None
  }
  let bits = magnitude.reinterpret_as_uint64()
  let encoded = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction = bits & 0x000fffffffffffffUL
  let significand = if encoded == 0 {
    fraction
  } else {
    fraction | 0x0010000000000000UL
  }
  let exponent = if encoded == 0 { -1074 } else { encoded - 1075 }
  let product = @bigint.BigInt::from_uint64(significand) *
    @bigint.BigInt::from_int64(nanos_per_unit)
  if product.is_zero() {
    return Some((0L, 0))
  }
  let whole = if exponent < 0 {
    // The original Number bits must denote an integral nanosecond duration.
    // Multiplying in binary64 first or parsing its decimal spelling would
    // silently change this representability decision.
    if product.ctz() < -exponent {
      return None
    }
    product >> -exponent
  } else {
    product << exponent
  }
  let billion = @bigint.BigInt::from_int(1000000000)
  let seconds = whole / billion
  if seconds > @bigint.BigInt::from_int64(316000000000L) {
    return None
  }
  let nanos = (whole % billion).to_int()
  Some(
    (
      if negative {
        -seconds.to_int64()
      } else {
        seconds.to_int64()
      },
      if negative {
        -nanos
      } else {
        nanos
      },
    ),
  )
}

///|
fn temporal_addition(
  expression : @lower.Expression,
  unit : String,
  value : Value,
  amount_value : Value,
) -> Result[Value, ScalarIssue] {
  if value is Null || amount_value is Null {
    return Ok(Null)
  }
  guard amount_value is Number(amount) else { return Err(InvalidOperand) }
  let date = value is Captured(@admitted.Date(_))
  if date && unit != "d" {
    return Err(InvalidOperand)
  }
  if date && amount.trunc() != amount {
    return Err(ArithmeticFailure)
  }
  guard temporal_difference_instant(value) is Some(instant) else {
    return Err(InvalidOperand)
  }
  guard temporal_duration_parts(amount, unit)
    is Some((seconds_delta, nanos_delta)) else {
    return Err(ArithmeticFailure)
  }
  let mut seconds = instant.seconds + seconds_delta
  let mut nanos = instant.nanoseconds + nanos_delta
  if nanos < 0 {
    seconds -= 1L
    nanos += 1000000000
  }
  if nanos >= 1000000000 {
    seconds += 1L
    nanos -= 1000000000
  }
  guard @admitted.epoch_parts_timestamp(seconds, nanos) is Some(text) else {
    return Err(ArithmeticFailure)
  }
  let contract = @contract.with_nullability(
    @lower.expression_contract(expression),
    false,
  )
  let checked = if date {
    @admitted.checked_date_value(text[:10].to_owned(), contract)
  } else {
    @admitted.checked_timestamp_value(text, contract)
  }
  match checked {
    Some(checked) => Ok(capture(checked.value))
    None => Err(InvalidOperand)
  }
}

///|
// The SQL interval amount is already checked int64. Never convert it to Number,
// including subtraction of min_int64; negate only the bounded exact product.
fn temporal_interval(
  expression : @lower.Expression,
  unit : String,
  value : Value,
  amount : Value,
  subtract : Bool,
) -> Result[Value, ScalarIssue] {
  if value is Null || amount is Null {
    return Ok(Null)
  }
  guard amount is Captured(@admitted.Signed64(integer)) else {
    return Err(InvalidOperand)
  }
  guard value is Captured(@admitted.Timestamp(_)) &&
    temporal_difference_instant(value) is Some(instant) else {
    return Err(InvalidOperand)
  }
  let factor = match unit {
    "ns" => 1L
    "us" => 1000L
    "ms" => 1000000L
    "s" => 1000000000L
    "m" => 60000000000L
    "h" => 3600000000000L
    "d" => 86400000000000L
    _ => return Err(InvalidOperand)
  }
  let product = @bigint.BigInt::from_int64(integer) *
    @bigint.BigInt::from_int64(factor)
  let delta = if subtract { -product } else { product }
  let billion = @bigint.BigInt::from_int(1000000000)
  let seconds_delta = delta / billion
  if seconds_delta < @bigint.BigInt::from_int64(-316000000000L) ||
    seconds_delta > @bigint.BigInt::from_int64(316000000000L) {
    return Err(ArithmeticFailure)
  }
  let mut seconds = instant.seconds + seconds_delta.to_int64()
  let mut nanos = instant.nanoseconds + (delta % billion).to_int()
  if nanos < 0 {
    seconds -= 1L
    nanos += 1000000000
  }
  if nanos >= 1000000000 {
    seconds += 1L
    nanos -= 1000000000
  }
  guard @admitted.epoch_parts_timestamp(seconds, nanos) is Some(text) else {
    return Err(ArithmeticFailure)
  }
  let contract = @contract.with_nullability(
    @lower.expression_contract(expression),
    false,
  )
  match @admitted.checked_timestamp_value(text, contract) {
    Some(checked) => Ok(Captured(checked.value))
    None => Err(InvalidOperand)
  }
}
