///|
// SQL conversion input is not canonical value-wire text. Admit an optional
// sign and decimal/hex digits, then publish the unchanged exact signed64 value
// domain. The caller precharges the complete original text before this scan.
fn cast_signed64_text(text : String) -> Int64? {
  let mut size = text.length()
  let mut start = 0
  while start < size && text[start] == ' ' {
    start += 1
  }
  if start == size {
    return None
  }
  let signed_start = if text[start] == '-' || text[start] == '+' {
    start + 1
  } else {
    start
  }
  let hexadecimal = signed_start + 1 < size &&
    text[signed_start] == '0' &&
    (text[signed_start + 1] == 'x' || text[signed_start + 1] == 'X')
  if !hexadecimal {
    while start < size && cast_signed64_space(text[start]) {
      start += 1
    }
  }
  while size > start && cast_signed64_space(text[size - 1]) {
    size -= 1
  }
  if start == size {
    return None
  }
  let negative = text[start] == '-'
  let mut index = if negative || text[start] == '+' { start + 1 } else { start }
  let radix = if hexadecimal { 16L } else { 10L }
  if hexadecimal {
    index += 2
  }
  if index == size {
    return None
  }
  let limit = if negative {
    -9223372036854775807L - 1L
  } else {
    -9223372036854775807L
  }
  let mut value = 0L
  while index < size {
    let unit = text[index]
    let digit = if unit >= '0' && unit <= '9' {
      unit.to_int() - '0'.to_int()
    } else if hexadecimal && unit >= 'a' && unit <= 'f' {
      unit.to_int() - 'a'.to_int() + 10
    } else if hexadecimal && unit >= 'A' && unit <= 'F' {
      unit.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    // Accumulate negatively so the signed minimum has no positive temporary.
    if value < (limit + digit.to_int64()) / radix {
      return None
    }
    value = value * radix - digit.to_int64()
    index += 1
  }
  Some(if negative { value } else { -value })
}

///|
fn cast_signed64_space(unit : UInt16) -> Bool {
  unit == ' ' || (unit >= '\t' && unit <= '\r')
}

///|
fn cast_signed64_decimal(value : @admitted.DecimalValue) -> Int64? {
  let coefficient = value.coefficient
  let negative = coefficient[0] == '-'
  let start = if negative { 1 } else { 0 }
  let whole_end = coefficient.length() - value.scale
  let limit = if negative {
    -9223372036854775807L - 1L
  } else {
    -9223372036854775807L
  }
  let mut whole = 0L
  for index = start; index < whole_end; index = index + 1 {
    let digit = (coefficient[index].to_int() - '0'.to_int()).to_int64()
    if whole < (limit + digit) / 10L {
      return None
    }
    whole = whole * 10L - digit
  }
  // A missing leading fractional digit is zero, not the first coefficient
  // digit: coefficient 5 at scale 2 denotes 0.05, not 0.5.
  if value.scale > 0 &&
    whole_end >= start &&
    whole_end < coefficient.length() &&
    coefficient[whole_end] >= '5' {
    if whole == limit {
      return None
    }
    whole -= 1L
  }
  Some(if negative { whole } else { -whole })
}

///|
fn cast_signed64_value(value : Value) -> Value? {
  let integer = match value {
    Captured(@admitted.Signed64(value)) => Some(value)
    Captured(@admitted.Decimal(value)) => cast_signed64_decimal(value)
    Text(text) => cast_signed64_text(text)
    Boolean(value) => Some(if value { 1L } else { 0L })
    Number(value) => {
      if value.is_nan() || value.is_inf() {
        return None
      }
      let whole = value.trunc()
      let fraction = value - whole
      let rounded = if fraction >= 0.5 {
        whole + 1.0
      } else if fraction <= -0.5 {
        whole - 1.0
      } else {
        whole
      }
      // Check the exclusive upper endpoint before the backend integer cast.
      if rounded < -9223372036854775808.0 || rounded >= 9223372036854775808.0 {
        None
      } else {
        Some(rounded.to_int64())
      }
    }
    _ => None
  }
  integer.map(value => capture(@admitted.signed64_value(value)))
}
