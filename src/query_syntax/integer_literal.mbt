///|
fn integer_digit(code : Int) -> Int {
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 55
  } else if code >= 97 && code <= 102 {
    code - 87
  } else {
    -1
  }
}

///|
/// Decode an unsigned query integer without binary64 rounding. Signs remain
/// expression operators; the existing Number contract admits only safe integers.
/// Callers retain the original token and charge their normal source-work budget.
pub fn exact_integer_literal(text : String) -> Int64? {
  let hex = text.has_prefix("0x") || text.has_prefix("0X")
  let start = if hex { 2 } else { 0 }
  let base = if hex { 16L } else { 10L }
  if text.length() <= start {
    return None
  }
  let mut value = 0L
  for index in start..<text.length() {
    let digit = integer_digit(text[index].to_int()).to_int64()
    if digit < 0L || digit >= base || value > (9007199254740991L - digit) / base {
      return None
    }
    value = value * base + digit
  }
  Some(value)
}
