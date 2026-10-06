///|
// The GoogleSQL JSON data profile is separate from machine document syntax.
// Keys are data, duplicate keys retain the first value, and every numeric
// token must survive a decimal round trip through the common binary64 domain.
// All input (including discarded duplicate values) is parsed and bounded.
pub fn parse_json_literal(
  source : String,
  limits : ParseLimits,
) -> Result[ParsedSource, ParseError] {
  let path = "<json-literal>"
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, path, Unavailable))
  }
  match @scalar.admit_utf8_length(source, limits.max_input_bytes) {
    Err(@scalar.MalformedUtf16(offset)) =>
      return Err(input_error(InvalidUtf16, path, Utf16Offset(offset)))
    Err(_) => return Err(input_error(InputLimit, path, Unavailable))
    Ok(_) => ()
  }
  let parser = Parser::make(
    source,
    path,
    limits,
    normalize_text=false,
    literal_json=true,
  )
  let node = parser.document() catch { ParseAbort(error) => return Err(error) }
  Ok({
    node,
    usage: {
      input_bytes: parser.byte_offset,
      nodes: parser.nodes,
      depth: parser.deepest,
    },
  })
}

///|
// Decimal significand/exponent comparison, not binary64 equality. Thus 0.1
// can round-trip while 0.10000000000000001 cannot. Grammar is already checked.
fn json_number_decimal_key(text : String) -> (Bool, String, Int64) {
  let negative = text.has_prefix("-")
  let digits = StringBuilder()
  let mut index = if negative { 1 } else { 0 }
  let mut fraction = 0L
  let mut after_point = false
  while index < text.length() && text[index] != 'e' && text[index] != 'E' {
    let ch = text[index]
    if ch == '.' {
      after_point = true
    } else {
      digits.write_char(ch.to_int().unsafe_to_char())
      if after_point {
        fraction += 1L
      }
    }
    index += 1
  }
  let mut exponent = 0L
  if index < text.length() {
    index += 1
    let sign = text[index]
    let exponent_negative = sign == '-'
    if sign == '+' || sign == '-' {
      index += 1
    }
    while index < text.length() {
      // Larger exponents cannot cancel a bounded mantissa into binary64.
      exponent = Int64::min(
        1000000L,
        exponent * 10L + (text[index].to_int() - 48).to_int64(),
      )
      index += 1
    }
    if exponent_negative {
      exponent = -exponent
    }
  }
  let digits = digits.to_string()
  let mut first = 0
  while first < digits.length() && digits[first] == '0' {
    first += 1
  }
  if first == digits.length() {
    return (false, "0", 0L)
  }
  let mut end = digits.length()
  while end > first && digits[end - 1] == '0' {
    end -= 1
  }
  (
    negative,
    digits[first:end].to_owned(),
    exponent - fraction + (digits.length() - end).to_int64(),
  )
}

///|
fn Parser::check_json_number_precision(
  self : Parser,
  start : Int,
  value : Double,
  path : Array[PathSegment],
) -> Unit raise ParseAbort {
  let spelling = self.source[start:self.offset].to_owned()
  if spelling.length() > 1500 ||
    json_number_decimal_key(spelling) !=
    json_number_decimal_key(value.to_string()) {
    self.fail(NumberPrecisionLoss, path)
  }
}
