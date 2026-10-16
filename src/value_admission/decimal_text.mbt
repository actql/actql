///|
/// Physical source-text conversion, separate from strict canonical wire
/// admission. This is the existing Salesforce digit/exponent algorithm shared
/// with other Connector observations; it neither rounds nor uses binary64.
pub(all) enum DecimalTextIssue {
  InvalidLimits
  InputLimit
  InvalidFormat
  OutOfRange
  BeyondScale
} derive(Eq, Debug)

///|
/// Return the Common fixed-scale spelling of the supplied decimal number text.
/// The caller must bound its original response and this retained string before
/// calling; this additional input ceiling is not funding or read authority.
pub fn normalize_decimal_text(
  lexeme : String,
  precision : Int,
  scale : Int,
  max_input_units : Int,
) -> Result[String, DecimalTextIssue] {
  if precision < 1 ||
    precision > 38 ||
    scale < 0 ||
    scale > precision ||
    max_input_units <= 0 {
    return Err(InvalidLimits)
  }
  if lexeme.length() > max_input_units {
    return Err(InputLimit)
  }
  let size = lexeme.length()
  let negative = size > 0 && lexeme[0] == '-'
  let mut index = if negative { 1 } else { 0 }
  let digits = StringBuilder()
  let integer_start = index
  while index < size && lexeme[index] >= '0' && lexeme[index] <= '9' {
    digits.write_char(lexeme[index].to_int().unsafe_to_char())
    index += 1
  }
  let integer_digits = index - integer_start
  if integer_digits == 0 || (integer_digits > 1 && lexeme[integer_start] == '0') {
    return Err(InvalidFormat)
  }
  let mut fraction_digits = 0
  if index < size && lexeme[index] == '.' {
    index += 1
    while index < size && lexeme[index] >= '0' && lexeme[index] <= '9' {
      digits.write_char(lexeme[index].to_int().unsafe_to_char())
      index += 1
      fraction_digits += 1
    }
    if fraction_digits == 0 {
      return Err(InvalidFormat)
    }
  }
  // The decimal exponent, bounded: beyond it a nonzero value is out of
  // range or scale whatever its digits.
  let mut exponent = 0
  let mut exponent_overflow = false
  if index < size && (lexeme[index] == 'e' || lexeme[index] == 'E') {
    index += 1
    let exponent_negative = index < size && lexeme[index] == '-'
    if index < size && (lexeme[index] == '-' || lexeme[index] == '+') {
      index += 1
    }
    let exponent_start = index
    while index < size && lexeme[index] >= '0' && lexeme[index] <= '9' {
      if exponent < 100000 {
        exponent = exponent * 10 + (lexeme[index].to_int() - 48)
      } else {
        exponent_overflow = true
      }
      index += 1
    }
    if index == exponent_start {
      return Err(InvalidFormat)
    }
    if exponent_negative {
      exponent = -exponent
    }
  }
  if index != size {
    return Err(InvalidFormat)
  }
  // The value is `digits × 10^(exponent − fraction_digits)`; its coefficient
  // at `scale` is `digits × 10^shift`.
  let all = digits.to_string()
  let mut first = 0
  while first < all.length() && all[first] == '0' {
    first += 1
  }
  if first == all.length() {
    // Zero, whatever its sign or exponent.
    return Ok(decimal_fixed_scale_text("0", false, scale))
  }
  let significant = all[first:].to_owned()
  if exponent_overflow {
    return Err(if exponent > 0 { OutOfRange } else { BeyondScale })
  }
  let shift = exponent.to_int64() -
    fraction_digits.to_int64() +
    scale.to_int64()
  let coefficient = if shift >= 0L {
    if significant.length().to_int64() + shift > precision.to_int64() {
      return Err(OutOfRange)
    }
    significant + "0".repeat(shift.to_int())
  } else {
    let kept = significant.length().to_int64() + shift
    let dropped = if kept > 0L {
      significant[kept.to_int():].to_owned()
    } else {
      significant
    }
    for unit in dropped {
      if unit != '0' {
        return Err(BeyondScale)
      }
    }
    if kept <= 0L {
      return Ok(decimal_fixed_scale_text("0", false, scale))
    }
    significant[:kept.to_int()].to_owned()
  }
  if coefficient.length() > precision {
    return Err(OutOfRange)
  }
  Ok(decimal_fixed_scale_text(coefficient, negative, scale))
}

///|
/// The ActQL canonical spelling of `coefficient × 10^(−scale)`.
fn decimal_fixed_scale_text(
  coefficient : String,
  negative : Bool,
  scale : Int,
) -> String {
  let padded = if coefficient.length() <= scale {
    "0".repeat(scale + 1 - coefficient.length()) + coefficient
  } else {
    coefficient
  }
  let integer_end = padded.length() - scale
  let text = if scale == 0 {
    padded
  } else {
    padded[:integer_end].to_owned() + "." + padded[integer_end:].to_owned()
  }
  if negative && coefficient != "0" {
    "-" + text
  } else {
    text
  }
}
