///|
fn yaml_number_spelling(text : String) -> Bool {
  let mut i = 0
  if text.length() > 0 && (text[0].to_int() == 0x2b || text[0].to_int() == 0x2d) {
    i += 1
  }
  let begin = i
  while i < text.length() && is_digit(text[i].to_int()) {
    i += 1
  }
  let before = i - begin
  let mut after = 0
  if i < text.length() && text[i].to_int() == 0x2e {
    i += 1
    let start = i
    while i < text.length() && is_digit(text[i].to_int()) {
      i += 1
    }
    after = i - start
  }
  if before == 0 && after == 0 {
    return false
  }
  if i < text.length() && (text[i].to_int() == 0x65 || text[i].to_int() == 0x45) {
    i += 1
    if i < text.length() &&
      (text[i].to_int() == 0x2b || text[i].to_int() == 0x2d) {
      i += 1
    }
    let start = i
    while i < text.length() && is_digit(text[i].to_int()) {
      i += 1
    }
    if i == start {
      return false
    }
  }
  i == text.length()
}

///|
/// Convert Core hexadecimal/octal integers with one ties-to-even rounding step.
/// Syntax has already been checked; leading zeroes do not consume significant bits.
fn yaml_radix_number(text : String, width : Int) -> Result[Double, ParseIssue] {
  let mut count = 0
  let mut leading = 0UL
  let mut guard_bit = false
  let mut sticky = false
  for i = 2; i < text.length(); i = i + 1 {
    let digit = hex_value(text[i].to_int()).unwrap()
    for bit = width - 1; bit >= 0; bit = bit - 1 {
      let one = (digit >> bit) & 1
      if count == 0 && one == 0 {
        continue
      }
      if count < 53 {
        leading = (leading << 1) | one.to_uint64()
      } else if count == 53 {
        guard_bit = one == 1
      } else if one == 1 {
        sticky = true
      }
      count += 1
      if count > 1024 {
        return Err(NumberOutOfRange)
      }
    }
  }
  if guard_bit && (sticky || (leading & 1UL) == 1UL) {
    leading += 1UL
  }
  let mut value = leading.to_double()
  for i = 53; i < count; i = i + 1 {
    value *= 2.0
  }
  if value.is_inf() {
    Err(NumberOutOfRange)
  } else {
    Ok(value)
  }
}

///|
fn yaml_resolve(text : String) -> Result[Value, ParseIssue] {
  match text {
    "" | "~" | "null" | "Null" | "NULL" => return Ok(Null)
    "true" | "True" | "TRUE" => return Ok(Bool(true))
    "false" | "False" | "FALSE" => return Ok(Bool(false))
    ".nan"
    | ".NaN"
    | ".NAN"
    | ".inf"
    | ".Inf"
    | ".INF"
    | "+.inf"
    | "+.Inf"
    | "+.INF"
    | "-.inf"
    | "-.Inf"
    | "-.INF" => return Err(NumberOutOfRange)
    _ => ()
  }
  if text.length() > 2 &&
    text[0].to_int() == 0x30 &&
    (text[1].to_int() == 0x78 || text[1].to_int() == 0x6f) {
    let width = if text[1].to_int() == 0x78 { 4 } else { 3 }
    let mut valid = true
    for i = 2; i < text.length(); i = i + 1 {
      match hex_value(text[i].to_int()) {
        Some(digit) if digit < 1 << width => ()
        _ => valid = false
      }
    }
    if valid {
      return match yaml_radix_number(text, width) {
        Ok(value) => Ok(Number(value))
        Err(error) => Err(error)
      }
    }
  }
  if yaml_number_spelling(text) {
    // The exact decimal converter accepts Core's leading zeroes and empty
    // fractional tail once the Core grammar has been established above.
    let parser = Parser::make(text, "<number>", {
      max_input_bytes: 0,
      max_nodes: 0,
      max_depth: 0,
    })
    parser.offset = text.length()
    let start = if text[0].to_int() == 0x2b { 1 } else { 0 }
    return Ok(Number(parser.read_binary64(start, []))) catch {
      ParseAbort(error) => Err(error.issue)
    }
  }
  match @canonical.validate_scalar_text(text) {
    Ok(_) => Ok(String(text))
    Err(_) => Err(InvalidYamlScalar)
  }
}
