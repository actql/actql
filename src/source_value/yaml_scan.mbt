///|
fn yaml_space(unit : Int) -> Bool {
  unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d
}

///|
fn yaml_break(unit : Int) -> Bool {
  unit == 0x0a || unit == 0x0d
}

///|
fn Parser::yaml_at(self : Parser, ahead : Int) -> Int {
  let index = self.offset + ahead
  if index >= self.source.length() {
    -1
  } else {
    self.source[index].to_int()
  }
}

///|
fn Parser::yaml_take(self : Parser) -> Int raise ParseAbort {
  let value = self.yaml_at(0)
  if (
      value >= 0 &&
      value < 0x20 &&
      value != 0x09 &&
      value != 0x0a &&
      value != 0x0d
    ) ||
    (value >= 0x7f && value < 0xa0 && value != 0x85) ||
    value == 0xfffe ||
    value == 0xffff {
    self.fail(InvalidYamlScalar, self.path)
  }
  self.advance_scalar(self.path)
}

///|
fn Parser::yaml_horizontal(self : Parser) -> Unit raise ParseAbort {
  while self.yaml_at(0) == 0x20 || self.yaml_at(0) == 0x09 {
    ignore(self.yaml_take())
  }
}

///|
fn Parser::yaml_newline(self : Parser) -> Unit raise ParseAbort {
  if self.yaml_at(0) == 0x0d {
    ignore(self.yaml_take())
    if self.yaml_at(0) == 0x0a {
      ignore(self.yaml_take())
    }
  } else if self.yaml_at(0) == 0x0a {
    ignore(self.yaml_take())
  } else {
    self.fail(UnexpectedToken, self.path)
  }
}

///|
fn Parser::yaml_skip(self : Parser) -> Unit raise ParseAbort {
  let mut prefix = self.column == 1
  let mut tab = false
  while true {
    let unit = self.yaml_at(0)
    if unit == 0x20 || unit == 0x09 {
      if prefix && unit == 0x09 {
        tab = true
      }
      ignore(self.yaml_take())
    } else if unit == 0x23 {
      if self.column != 1 &&
        self.offset > 0 &&
        !yaml_space(self.source[self.offset - 1].to_int()) {
        self.fail(InvalidYamlScalar, self.path)
      }
      while self.yaml_at(0) >= 0 && !yaml_break(self.yaml_at(0)) {
        ignore(self.yaml_take())
      }
    } else if yaml_break(unit) {
      self.yaml_newline()
      prefix = true
      tab = false
    } else {
      if tab && unit >= 0 {
        self.fail(InvalidYamlIndentation, self.path)
      }
      break
    }
  }
}

///|
fn Parser::yaml_indicator(self : Parser, unit : Int) -> Bool {
  self.yaml_at(0) == unit &&
  (self.yaml_at(1) < 0 || yaml_space(self.yaml_at(1)))
}

///|
fn Parser::yaml_marker(self : Parser, unit : Int) -> Bool {
  self.column == 1 &&
  self.yaml_at(0) == unit &&
  self.yaml_at(1) == unit &&
  self.yaml_at(2) == unit &&
  (self.yaml_at(3) < 0 || yaml_space(self.yaml_at(3)))
}

///|
/// Find an implicit scalar-key separator without inspecting descendant values.
fn Parser::yaml_colon(self : Parser, flow : Bool) -> Int? {
  let start = self.offset
  let mut i = start
  let mut quote = 0
  let mut quoted_end = false
  if self.yaml_at(0) == 0x22 || self.yaml_at(0) == 0x27 {
    quote = self.yaml_at(0)
    i += 1
  }
  while i < self.source.length() {
    let unit = self.source[i].to_int()
    if yaml_break(unit) {
      return None
    }
    if quote != 0 {
      if quote == 0x22 && unit == 0x5c {
        i += 2
        continue
      }
      if unit == quote {
        if quote == 0x27 &&
          i + 1 < self.source.length() &&
          self.source[i + 1].to_int() == quote {
          i += 2
          continue
        }
        quote = 0
        quoted_end = true
      }
    } else {
      let next = if i + 1 < self.source.length() {
        self.source[i + 1].to_int()
      } else {
        -1
      }
      if unit == 0x3a &&
        (
          (flow && quoted_end) ||
          next < 0 ||
          yaml_space(next) ||
          (
            flow &&
            (
              next == 0x2c ||
              next == 0x5b ||
              next == 0x5d ||
              next == 0x7b ||
              next == 0x7d
            )
          )
        ) {
        return Some(i)
      }
      if unit == 0x23 && (i == start || yaml_space(self.source[i - 1].to_int())) {
        return None
      }
      if unit == 0x5b ||
        unit == 0x7b ||
        (flow && (unit == 0x2c || unit == 0x5d || unit == 0x7d)) {
        return None
      }
      if quoted_end && unit != 0x20 && unit != 0x09 {
        return None
      }
    }
    i += 1
  }
  None
}

///|
fn yaml_normalized(chars : Array[Char]) -> String {
  // Scalars were checked while reading or decoding escapes.
  @canonical.normalize_nfc_lf(String::from_array(chars)).unwrap()
}

///|
/// Only spaces satisfy indentation; subsequent tabs are separation.
fn Parser::yaml_quoted_prefix(
  self : Parser,
  parent_indent : Int,
) -> Unit raise ParseAbort {
  let mut spaces = 0
  while self.yaml_at(0) == 0x20 {
    ignore(self.yaml_take())
    spaces += 1
  }
  self.yaml_horizontal()
  if !yaml_break(self.yaml_at(0)) && spaces <= parent_indent {
    self.fail(InvalidYamlIndentation, self.path)
  }
}

///|
fn Parser::yaml_quoted(
  self : Parser,
  key : Bool,
  parent_indent : Int,
) -> String raise ParseAbort {
  let quote = self.yaml_take()
  let chars : Array[Char] = []
  let mut trailing_raw_space = 0
  while true {
    let unit = self.yaml_at(0)
    if unit < 0 {
      self.fail(UnexpectedEnd, self.path)
    }
    if unit == quote {
      ignore(self.yaml_take())
      if quote == 0x27 && self.yaml_at(0) == quote {
        ignore(self.yaml_take())
        chars.push('\'')
        trailing_raw_space = 0
        continue
      }
      return yaml_normalized(chars)
    }
    if yaml_break(unit) {
      if key {
        self.fail(InvalidYamlScalar, self.path)
      }
      // Escaped whitespace is content, not foldable source separation.
      for i = 0; i < trailing_raw_space; i = i + 1 {
        ignore(chars.pop())
      }
      trailing_raw_space = 0
      self.yaml_newline()
      self.yaml_quoted_prefix(parent_indent)
      let mut empty = 0
      while yaml_break(self.yaml_at(0)) {
        empty += 1
        self.yaml_newline()
        self.yaml_quoted_prefix(parent_indent)
      }
      if self.column - 1 <= parent_indent ||
        self.yaml_marker(0x2d) ||
        self.yaml_marker(0x2e) {
        self.fail(InvalidYamlIndentation, self.path)
      }
      if empty == 0 {
        chars.push(' ')
      } else {
        for i = 0; i < empty; i = i + 1 {
          chars.push('\n')
        }
      }
      continue
    }
    if quote == 0x22 && unit == 0x5c {
      trailing_raw_space = 0
      ignore(self.yaml_take())
      let start = self.point()
      let escape = self.yaml_at(0)
      if yaml_break(escape) {
        if key {
          self.fail(InvalidYamlScalar, self.path)
        }
        self.yaml_newline()
        self.yaml_quoted_prefix(parent_indent)
        while yaml_break(self.yaml_at(0)) {
          chars.push('\n')
          self.yaml_newline()
          self.yaml_quoted_prefix(parent_indent)
        }
        if self.column - 1 <= parent_indent {
          self.fail(InvalidYamlIndentation, self.path)
        }
        continue
      }
      ignore(self.yaml_take())
      let scalar = match escape {
        0x30 => 0
        0x61 => 7
        0x62 => 8
        0x74 | 0x09 => 9
        0x6e => 10
        0x76 => 11
        0x66 => 12
        0x72 => 13
        0x65 => 27
        0x20 => 32
        0x22 => 34
        0x2f => 47
        0x5c => 92
        0x4e => 0x85
        0x5f => 0xa0
        0x4c => 0x2028
        0x50 => 0x2029
        0x75 => self.parse_escape_scalar(self.path)
        0x78 | 0x55 => {
          let count = if escape == 0x78 { 2 } else { 8 }
          let mut value = 0L
          for i = 0; i < count; i = i + 1 {
            let point = self.point()
            let digit = match hex_value(self.yaml_at(0)) {
              Some(value) => value
              None =>
                raise self.failure_at(InvalidUnicodeEscape, self.path, point)
            }
            ignore(self.yaml_take())
            value = value * 16L + digit.to_int64()
          }
          if value > 0x10ffffL || (value >= 0xd800L && value <= 0xdfffL) {
            raise self.failure_at(InvalidUnicodeEscape, self.path, start)
          }
          value.to_int()
        }
        _ => raise self.failure_at(InvalidEscape, self.path, start)
      }
      chars.push(scalar.unsafe_to_char())
    } else {
      chars.push(self.yaml_take().unsafe_to_char())
      trailing_raw_space = if unit == 0x20 || unit == 0x09 {
        trailing_raw_space + 1
      } else {
        0
      }
    }
  } nobreak {
    self.fail(UnexpectedEnd, self.path)
  }
}

///|
/// Locate a plain-scalar continuation without consuming sibling layout.
fn Parser::yaml_continuation(
  self : Parser,
  parent_indent : Int,
  flow : Bool,
) -> Int? {
  let mut i = self.offset
  let mut breaks = 0
  while i < self.source.length() && yaml_break(self.source[i].to_int()) {
    let cr = self.source[i].to_int() == 0x0d
    i += 1
    if cr && i < self.source.length() && self.source[i].to_int() == 0x0a {
      i += 1
    }
    breaks += 1
    let begin = i
    while i < self.source.length() && self.source[i].to_int() == 0x20 {
      i += 1
    }
    if i >= self.source.length() {
      return None
    }
    let unit = self.source[i].to_int()
    if yaml_break(unit) {
      continue
    }
    if unit == 0x23 || unit == 0x09 {
      return None
    }
    if i - begin <= parent_indent {
      return None
    }
    if flow && (unit == 0x2c || unit == 0x5d || unit == 0x7d) {
      return None
    }
    if i == begin &&
      i + 2 < self.source.length() &&
      (unit == 0x2d || unit == 0x2e) &&
      self.source[i + 1].to_int() == unit &&
      self.source[i + 2].to_int() == unit &&
      (i + 3 == self.source.length() || yaml_space(self.source[i + 3].to_int())) {
      return None
    }
    return Some(breaks)
  }
  None
}

///|
fn Parser::yaml_plain(
  self : Parser,
  flow : Bool,
  key : Bool,
  parent_indent : Int,
  multiline_key? : Bool = false,
) -> Value raise ParseAbort {
  let start = self.point()
  let first = self.yaml_at(0)
  if first == 0x26 || first == 0x2a || first == 0x21 {
    self.fail(ForbiddenYamlFeature, self.path)
  }
  if first == 0x40 ||
    first == 0x60 ||
    first == 0x25 ||
    first == 0x7c ||
    first == 0x3e ||
    first == 0x5b ||
    first == 0x7b ||
    first == 0x5d ||
    first == 0x7d ||
    first == 0x2c ||
    (
      (first == 0x2d || first == 0x3f || first == 0x3a) &&
      self.yaml_indicator(first)
    ) {
    self.fail(InvalidYamlScalar, self.path)
  }
  let chars : Array[Char] = []
  while true {
    let unit = self.yaml_at(0)
    if unit < 0 {
      break
    }
    if flow &&
      (
        unit == 0x2c ||
        unit == 0x5d ||
        unit == 0x7d ||
        unit == 0x5b ||
        unit == 0x7b
      ) {
      break
    }
    if unit == 0x3a &&
      (
        self.yaml_at(1) < 0 ||
        yaml_space(self.yaml_at(1)) ||
        (
          flow &&
          (
            self.yaml_at(1) == 0x2c ||
            self.yaml_at(1) == 0x5d ||
            self.yaml_at(1) == 0x7d ||
            self.yaml_at(1) == 0x5b ||
            self.yaml_at(1) == 0x7b
          )
        )
      ) {
      if key {
        break
      } else {
        self.fail(InvalidYamlScalar, self.path)
      }
    }
    if unit == 0x23 &&
      (
        chars.is_empty() ||
        chars[chars.length() - 1] == ' ' ||
        chars[chars.length() - 1] == '\t'
      ) {
      break
    }
    if yaml_break(unit) {
      if key && !multiline_key {
        break
      }
      let count = match self.yaml_continuation(parent_indent, flow) {
        Some(count) => count
        None => break
      }
      while chars.length() > 0 &&
            (
              chars[chars.length() - 1] == ' ' ||
              chars[chars.length() - 1] == '\t'
            ) {
        ignore(chars.pop())
      }
      for i = 0; i < count; i = i + 1 {
        self.yaml_newline()
        self.yaml_horizontal()
      }
      if count == 1 {
        chars.push(' ')
      } else {
        for i = 1; i < count; i = i + 1 {
          chars.push('\n')
        }
      }
      continue
    }
    chars.push(self.yaml_take().unsafe_to_char())
  }
  while chars.length() > 0 &&
        (chars[chars.length() - 1] == ' ' || chars[chars.length() - 1] == '\t') {
    ignore(chars.pop())
    self.offset -= 1
    self.byte_offset -= 1
    self.column -= 1
  }
  if chars.is_empty() {
    self.fail(InvalidYamlScalar, self.path)
  }
  match yaml_resolve(String::from_array(chars)) {
    Ok(value) => value
    Err(error) => raise self.failure_at(error, self.path, start)
  }
}
