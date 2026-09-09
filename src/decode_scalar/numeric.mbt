///|
/// Read an integral binary64 value in the safe-integer range without rounding.
/// Negative zero converts to integer zero; canonical admission is separate.
pub fn read_safe_integer(value : Double) -> Int64? {
  if read_integer_number(value) is Some(_) &&
    value >= -9007199254740991.0 &&
    value <= 9007199254740991.0 {
    Some(value.to_int64())
  } else {
    None
  }
}

///|
/// Integral finite binary64 admission without narrowing or a safe-integer cap.
/// This does not prove that a neighboring integer is exactly representable.
/// Domain consumers retain their own sign, size and canonical-zero policies.
pub fn read_integer_number(value : Double) -> Double? {
  if read_finite_number(value) is Some(_) && value.trunc() == value {
    Some(value)
  } else {
    None
  }
}

///|
/// Admission only: preserve all finite binary64 bits, including negative zero.
/// Canonical negative-zero policy belongs to the canonical value boundary.
pub fn read_finite_number(value : Double) -> Double? {
  if value.is_nan() || value.is_inf() {
    None
  } else {
    Some(value)
  }
}

///|
pub fn read_int32(value : Double) -> Int? {
  match read_safe_integer(value) {
    Some(value) if value >= -2147483648L && value <= 2147483647L =>
      Some(value.to_int())
    Some(_) | None => None
  }
}

///|
/// A fixed-width UInt64 word, not a permissive integer literal. Both hex cases
/// are accepted; whitespace, signs, prefixes, and short/long forms are rejected.
pub fn read_hex_uint64(text : String) -> UInt64? {
  if text.length() != 16 {
    return None
  }
  let mut value = 0UL
  for index in 0..<text.length() {
    let code = text[index].to_int()
    let digit = if code >= 0x30 && code <= 0x39 {
      code - 0x30
    } else if code >= 0x41 && code <= 0x46 {
      code - 0x41 + 10
    } else if code >= 0x61 && code <= 0x66 {
      code - 0x61 + 10
    } else {
      return None
    }
    value = (value << 4) | digit.to_uint64()
  }
  Some(value)
}

///|
/// Local errors for canonical signed decimal Int64 text, not the Decimal type.
pub(all) enum DecimalIssue {
  InvalidSyntax
  NonCanonical
  RangeExceeded
} derive(Eq, Debug)

///|
/// Check syntax, canonical spelling, then Int64 range before arithmetic.
/// Callers bound input length before this full syntax scan.
pub fn read_decimal_int64(text : String) -> Result[Int64, DecimalIssue] {
  if text.is_empty() {
    return Err(InvalidSyntax)
  }
  let negative = text[0] == '-'
  let start = if negative { 1 } else { 0 }
  if start == text.length() {
    return Err(InvalidSyntax)
  }
  for index in start..<text.length() {
    let unit = text[index].to_int()
    if unit < 0x30 || unit > 0x39 {
      return Err(InvalidSyntax)
    }
  }
  if (text[start] == '0' && text.length() - start > 1) ||
    (negative && text.length() == 2 && text[1] == '0') {
    return Err(NonCanonical)
  }
  let digits = text.length() - start
  let bound = if negative {
    "9223372036854775808"
  } else {
    "9223372036854775807"
  }
  if digits > 19 {
    return Err(RangeExceeded)
  }
  if digits == 19 {
    for offset = 0; offset < 19; offset = offset + 1 {
      let actual = text[start + offset]
      let limit = bound[offset]
      if actual > limit {
        return Err(RangeExceeded)
      }
      if actual < limit {
        break
      }
    }
  }
  let mut result = 0L
  for index = start; index < text.length(); index = index + 1 {
    let unit = text[index].to_int()
    let digit = (unit - 0x30).to_int64()
    result = if negative { result * 10L - digit } else { result * 10L + digit }
  }
  Ok(result)
}
