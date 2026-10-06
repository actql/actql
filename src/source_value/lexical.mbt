///|
fn hex_value(unit : Int) -> Int? {
  if unit >= 0x30 && unit <= 0x39 {
    Some(unit - 0x30)
  } else if unit >= 0x41 && unit <= 0x46 {
    Some(unit - 0x41 + 10)
  } else if unit >= 0x61 && unit <= 0x66 {
    Some(unit - 0x61 + 10)
  } else {
    None
  }
}

///|
fn Parser::parse_hex4(
  self : Parser,
  path : Array[PathSegment],
) -> Int raise ParseAbort {
  let mut value = 0
  for digit_index = 0; digit_index < 4; digit_index = digit_index + 1 {
    let point = self.point()
    let unit = match self.peek() {
      Some(unit) => unit
      None => self.fail(UnexpectedEnd, path)
    }
    let digit = match hex_value(unit) {
      Some(value) => value
      None => raise self.failure_at(InvalidUnicodeEscape, path, point)
    }
    ignore(self.advance_scalar(path))
    value = value * 16 + digit
  }
  value
}

///|
fn Parser::parse_escape_scalar(
  self : Parser,
  path : Array[PathSegment],
) -> Int raise ParseAbort {
  let first = self.parse_hex4(path)
  if first >= 0xD800 && first <= 0xDBFF {
    if self.peek() != Some(0x5C) {
      self.fail(InvalidUnicodeEscape, path)
    }
    ignore(self.advance_scalar(path))
    if self.peek() != Some(0x75) {
      self.fail(InvalidUnicodeEscape, path)
    }
    ignore(self.advance_scalar(path))
    let low = self.parse_hex4(path)
    if low < 0xDC00 || low > 0xDFFF {
      self.fail(InvalidUnicodeEscape, path)
    }
    return 0x10000 + ((first - 0xD800) << 10) + low - 0xDC00
  }
  if first >= 0xDC00 && first <= 0xDFFF {
    self.fail(InvalidUnicodeEscape, path)
  }
  first
}

///|
fn Parser::parse_string(
  self : Parser,
  path : Array[PathSegment],
  key? : Bool = false,
) -> (String, Span) raise ParseAbort {
  let start = self.point()
  if self.peek() != Some(0x22) {
    self.fail(InvalidString, path)
  }
  ignore(self.advance_scalar(path))
  let output = StringBuilder()
  while true {
    let unit = match self.peek() {
      Some(value) => value
      None => self.fail(UnexpectedEnd, path)
    }
    if unit == 0x22 {
      ignore(self.advance_scalar(path))
      let text = output.to_string()
      let decoded = if key && self.normalize_text {
        match @canonical.normalize_nfc_lf(text) {
          Ok(value) => value
          Err(_) => self.fail(InvalidUnicodeEscape, path)
        }
      } else {
        text
      }
      return (decoded, self.span(start))
    }
    if unit < 0x20 {
      self.fail(InvalidString, path)
    }
    if unit != 0x5C {
      output.write_char(self.advance_scalar(path).unsafe_to_char())
      continue
    }
    ignore(self.advance_scalar(path))
    let escaped = match self.peek() {
      Some(value) => value
      None => self.fail(UnexpectedEnd, path)
    }
    let escape_start = self.point()
    ignore(self.advance_scalar(path))
    match escaped {
      0x22 => output.write_char('"')
      0x5C => output.write_char('\\')
      0x2F => output.write_char('/')
      0x62 => output.write_char('\b')
      0x66 => output.write_char('\f')
      0x6E => output.write_char('\n')
      0x72 => output.write_char('\r')
      0x74 => output.write_char('\t')
      0x75 => output.write_char(self.parse_escape_scalar(path).unsafe_to_char())
      _ => raise self.failure_at(InvalidEscape, path, escape_start)
    }
  } nobreak {
    self.fail(UnexpectedEnd, path)
  }
}

///|
fn is_digit(unit : Int) -> Bool {
  unit >= 0x30 && unit <= 0x39
}

///|
fn Parser::consume_ascii(
  self : Parser,
  path : Array[PathSegment],
) -> Unit raise ParseAbort {
  ignore(self.advance_scalar(path))
}

///|
fn Parser::parse_number(
  self : Parser,
  path : Array[PathSegment],
) -> Node raise ParseAbort {
  let start = self.point()
  let start_offset = self.offset
  if self.peek() == Some(0x2D) {
    self.consume_ascii(path)
  }
  match self.peek() {
    Some(0x30) => {
      self.consume_ascii(path)
      if self.peek() is Some(next) && is_digit(next) {
        self.fail(InvalidNumber, path)
      }
    }
    Some(unit) if unit >= 0x31 && unit <= 0x39 => {
      self.consume_ascii(path)
      while self.peek() is Some(next) && is_digit(next) {
        self.consume_ascii(path)
      }
    }
    _ => self.fail(InvalidNumber, path)
  }
  if self.peek() == Some(0x2E) {
    self.consume_ascii(path)
    if !(self.peek() is Some(next) && is_digit(next)) {
      self.fail(InvalidNumber, path)
    }
    while self.peek() is Some(next) && is_digit(next) {
      self.consume_ascii(path)
    }
  }
  if self.peek() is Some(exponent) && (exponent == 0x65 || exponent == 0x45) {
    self.consume_ascii(path)
    if self.peek() is Some(sign) && (sign == 0x2B || sign == 0x2D) {
      self.consume_ascii(path)
    }
    if !(self.peek() is Some(next) && is_digit(next)) {
      self.fail(InvalidNumber, path)
    }
    while self.peek() is Some(next) && is_digit(next) {
      self.consume_ascii(path)
    }
  }
  let number = self.read_binary64(start_offset, path)
  if self.literal_json {
    self.check_json_number_precision(start_offset, number, path)
  }
  { value: Number(number), span: self.span(start), }
}

///|
fn Parser::consume_literal(
  self : Parser,
  spelling : String,
  path : Array[PathSegment],
) -> Unit raise ParseAbort {
  for index = 0; index < spelling.length(); index = index + 1 {
    if self.peek() != Some(spelling[index].to_int()) {
      self.fail(UnexpectedToken, path)
    }
    self.consume_ascii(path)
  }
}
