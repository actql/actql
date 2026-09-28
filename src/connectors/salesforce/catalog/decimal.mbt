///|
/// The largest described precision declared as `decimal(P,S)`. Salesforce
/// holds a Number field as a binary64 double and replies with a JSON number.
/// Any decimal of at most 15 significant digits is recovered unchanged from
/// the nearest binary64 value, and two such decimals never share one. So for
/// a field whose every value has at most 15 digits, the reply is either that
/// decimal or carries digits outside the declared scale, which is refused.
/// This is the round-trip property, not exactness: the binary64 value of
/// `0.1` is not 0.1, and the connector never reads that binary64 value. At 16
/// or more digits two stored decimals can share one double, so another
/// decimal within the declared scale could come back; such fields are not
/// declared.
const MAX_EXACT_DOUBLE_PRECISION : Int = 15

///|
/// The ActQL `decimal(P,S)` a Salesforce Number (`double`) field is declared
/// as, from its described precision and scale, or none.
fn double_decimal(field : FieldMetadata) -> (Int, Int)? {
  guard field.native_type == "double" &&
    field.precision is Some(precision) &&
    field.scale is Some(scale) &&
    precision >= 1 &&
    precision <= MAX_EXACT_DOUBLE_PRECISION &&
    scale >= 0 &&
    scale <= precision else {
    return None
  }
  Some((precision, scale))
}

///|
/// Why a number is not a value of `decimal(P,S)`.
priv enum DecimalIssue {
  /// Not a JSON number or canonical decimal text.
  DecimalFormat
  /// More integer digits than P − S.
  DecimalRange
  /// A nonzero digit beyond scale S.
  DecimalScale
}

///|
/// The ActQL fixed-scale text of the JSON number `lexeme` as
/// `decimal(precision, scale)`, from its digits alone: no binary64 value is
/// formed. Trailing zeros beyond the scale are exact and dropped; a nonzero
/// digit beyond it is `DecimalScale`, never rounded.
fn json_number_decimal(
  lexeme : String,
  precision : Int,
  scale : Int,
) -> Result[String, DecimalIssue] {
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
    return Err(DecimalFormat)
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
      return Err(DecimalFormat)
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
      return Err(DecimalFormat)
    }
    if exponent_negative {
      exponent = -exponent
    }
  }
  if index != size {
    return Err(DecimalFormat)
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
    return Ok(fixed_scale_text("0", false, scale))
  }
  let significant = all[first:].to_owned()
  if exponent_overflow {
    return Err(if exponent > 0 { DecimalRange } else { DecimalScale })
  }
  let shift = exponent - fraction_digits + scale
  let coefficient = if shift >= 0 {
    if significant.length() + shift > precision {
      return Err(DecimalRange)
    }
    significant + "0".repeat(shift)
  } else {
    let kept = significant.length() + shift
    let dropped = if kept > 0 {
      significant[kept:].to_owned()
    } else {
      significant
    }
    for unit in dropped {
      if unit != '0' {
        return Err(DecimalScale)
      }
    }
    if kept <= 0 {
      return Ok(fixed_scale_text("0", false, scale))
    }
    significant[:kept].to_owned()
  }
  if coefficient.length() > precision {
    return Err(DecimalRange)
  }
  Ok(fixed_scale_text(coefficient, negative, scale))
}

///|
/// The ActQL canonical spelling of `coefficient × 10^(−scale)`.
fn fixed_scale_text(
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

///|
/// Why an approved decimal value is refused before it is sent: it must be
/// the ActQL canonical spelling of a `decimal(P,S)` value.
fn decimal_write_issue(
  text : String,
  precision : Int,
  scale : Int,
  field : String,
) -> WriteBodyIssue? {
  match json_number_decimal(text, precision, scale) {
    Ok(canonical) if canonical == text => None
    Ok(_) | Err(DecimalFormat) => Some(InvalidValue(field))
    Err(DecimalRange) => Some(ValueOutOfRange(field))
    Err(DecimalScale) => Some(ValueBeyondScale(field))
  }
}

///|
/// The exact JSON text of the value at `cursor`, from the bytes it was
/// parsed from.
fn source_lexeme(source : Bytes, cursor : @decode.Cursor) -> String? {
  let span = @decode.cursor_span(cursor)
  if span.start_byte < 0 ||
    span.end_byte > source.length() ||
    span.start_byte >= span.end_byte {
    return None
  }
  let text = StringBuilder()
  for index in span.start_byte..<span.end_byte {
    let byte = source[index]
    if byte >= 128 {
      return None
    }
    text.write_char(byte.to_int().unsafe_to_char())
  }
  Some(text.to_string())
}
