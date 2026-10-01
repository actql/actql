///|
pub(all) enum Lexeme {
  Word(String)
  QuotedName(String)
  Text(String)
  Numeric(String)
  Parameter(String)
  Operator(String)
  Symbol(Int)
  Pipe
  End
} derive(Eq, Debug)

///|
pub struct Token {
  value : Lexeme
  start : Int
  end : Int
  annotation_compatible : Bool
} derive(Eq, Debug)

///|
pub(all) enum LexicalIssue {
  UnexpectedEnd
  UnexpectedToken
  InvalidEscape
  InvalidScalar
  EmptyIdentifier
  UnterminatedComment
  InvalidNumber
  InvalidParameter
} derive(Eq, Debug)

///|
priv suberror LexicalAbort {
  LexicalAbort(LexicalIssue, Int)
} derive(Debug)

///|
// Only constructed after the complete input passes original-Unicode admission.
priv struct Scanner {
  text : String
  budget : Budget
  mut offset : Int
  mut byte_offset : Int
}

///|
fn Scanner::peek(self : Scanner, ahead? : Int = 0) -> Int? {
  let offset = self.offset + ahead
  if offset < self.text.length() {
    Some(self.text[offset].to_int())
  } else {
    None
  }
}

///|
fn Scanner::advance(self : Scanner) -> Int raise {
  self.budget.charge(Work, 1, self.byte_offset)
  let first = match self.peek() {
    Some(n) => n
    None => raise LexicalAbort(UnexpectedEnd, self.byte_offset)
  }
  let scalar = if first >= 0xd800 && first <= 0xdbff {
    let second = self.text[self.offset + 1].to_int()
    self.offset += 2
    0x10000 + ((first - 0xd800) << 10) + second - 0xdc00
  } else {
    self.offset += 1
    first
  }
  self.byte_offset += if scalar < 0x80 {
    1
  } else if scalar < 0x800 {
    2
  } else if scalar < 0x10000 {
    3
  } else {
    4
  }
  scalar
}

///|
fn Scanner::trivia(self : Scanner) -> Unit raise {
  if self.offset == 0 && self.peek() == Some(0xfeff) {
    ignore(self.advance())
  }
  while true {
    match self.peek() {
      Some(0x20 | 0x09 | 0x0a | 0x0d) => ignore(self.advance())
      Some(0x2d) if self.peek(ahead=1) == Some(0x2d) =>
        while self.peek() is Some(n) && n != 0x0a && n != 0x0d {
          ignore(self.advance())
        }
      Some(0x2f) if self.peek(ahead=1) == Some(0x2a) => {
        let start = self.byte_offset
        ignore(self.advance())
        ignore(self.advance())
        while true {
          if self.peek() == None {
            raise LexicalAbort(UnterminatedComment, start)
          }
          if self.peek() == Some(0x2a) && self.peek(ahead=1) == Some(0x2f) {
            ignore(self.advance())
            ignore(self.advance())
            break
          }
          ignore(self.advance())
        }
      }
      _ => break
    }
  }
}

///|
fn identifier_start(n : Int) -> Bool {
  n == 0x5f || (n >= 0x41 && n <= 0x5a) || (n >= 0x61 && n <= 0x7a)
}

///|
fn Scanner::escaped_scalar(self : Scanner, digits : Int) -> Int raise {
  let start = self.byte_offset
  let mut value = 0
  for _ in 0..<digits {
    let digit = match self.peek() {
      Some(n) if n >= 0x30 && n <= 0x39 => n - 0x30
      Some(n) if n >= 0x41 && n <= 0x46 => n - 0x41 + 10
      Some(n) if n >= 0x61 && n <= 0x66 => n - 0x61 + 10
      _ => raise LexicalAbort(InvalidEscape, self.byte_offset)
    }
    // Reject overflow before accumulation, including eight-digit escapes.
    if value > (0x10ffff - digit) / 16 {
      raise LexicalAbort(InvalidScalar, start)
    }
    value = value * 16 + digit
    ignore(self.advance())
  }
  if value >= 0xd800 && value <= 0xdfff {
    raise LexicalAbort(InvalidScalar, start)
  }
  value
}

///|
fn Scanner::quoted(
  self : Scanner,
  delimiter : Int,
  raw? : Bool = false,
) -> (String, Bool) raise {
  let start = self.byte_offset
  let triple = delimiter != 0x60 &&
    self.peek(ahead=1) == Some(delimiter) &&
    self.peek(ahead=2) == Some(delimiter)
  ignore(self.advance())
  if triple {
    ignore(self.advance())
    ignore(self.advance())
  }
  let output = StringBuilder()
  let mut annotation_compatible = !raw && !triple
  while true {
    let n = match self.peek() {
      Some(n) => n
      None => raise LexicalAbort(UnexpectedEnd, self.byte_offset)
    }
    if n == delimiter &&
      (
        !triple ||
        (
          self.peek(ahead=1) == Some(delimiter) &&
          self.peek(ahead=2) == Some(delimiter)
        )
      ) {
      ignore(self.advance())
      if triple {
        ignore(self.advance())
        ignore(self.advance())
      }
      let result = output.to_string()
      if delimiter == 0x60 && result.is_empty() {
        raise LexicalAbort(EmptyIdentifier, start)
      }
      return (result, annotation_compatible)
    }
    if (!triple && (n == 0x0a || n == 0x0d)) || (delimiter == 0x60 && n < 0x20) {
      raise LexicalAbort(UnexpectedToken, self.byte_offset)
    }
    // Plain query strings forbid raw newlines, not every control scalar.
    // The historical annotation language still requires escaped controls.
    if n < 0x20 {
      annotation_compatible = false
    }
    let scalar = if n == 0x5c {
      ignore(self.advance())
      let at = self.byte_offset
      let escaped = self.advance()
      if raw {
        if !triple && (escaped == 0x0a || escaped == 0x0d) {
          raise LexicalAbort(UnexpectedToken, at)
        }
        // Raw escaping protects the following delimiter without decoding it.
        // Both scalars belong to the value; each is accounted before append.
        self.budget.charge(LiteralBytes, 1, at)
        output.write_char('\\')
        escaped
      } else {
        // Keep the historical Graph annotation profile distinct from query
        // strings. Both use this bounded decoder; query-only escape forms must
        // not become newly valid annotation keys or field designations.
        if delimiter == 0x22 &&
          !(escaped == 0x5c ||
          escaped == 0x22 ||
          escaped == 0x6e ||
          escaped == 0x72 ||
          escaped == 0x74 ||
          escaped == 0x75 ||
          escaped == 0x55) {
          annotation_compatible = false
        }
        match escaped {
          0x5c => 0x5c
          0x27 | 0x22 if delimiter != 0x60 => escaped
          0x60 => 0x60
          0x61 if delimiter != 0x60 => 0x07
          0x62 if delimiter != 0x60 => 0x08
          0x66 if delimiter != 0x60 => 0x0c
          0x6e if delimiter == 0x27 || delimiter == 0x22 => 0x0a
          0x72 if delimiter == 0x27 || delimiter == 0x22 => 0x0d
          0x74 if delimiter == 0x27 || delimiter == 0x22 => 0x09
          0x76 if delimiter != 0x60 => 0x0b
          0x3f if delimiter != 0x60 => 0x3f
          0x78 | 0x58 if delimiter != 0x60 => self.escaped_scalar(2)
          0x30..=0x37 if delimiter != 0x60 => {
            let mut value = escaped - 0x30
            for _ in 0..<2 {
              let next = match self.peek() {
                Some(n) if n >= 0x30 && n <= 0x37 => n - 0x30
                _ => raise LexicalAbort(InvalidEscape, self.byte_offset)
              }
              value = value * 8 + next
              ignore(self.advance())
            }
            value
          }
          0x75 => self.escaped_scalar(4)
          0x55 => self.escaped_scalar(8)
          _ => raise LexicalAbort(InvalidEscape, at)
        }
      }
    } else if triple && n == 0x0d {
      // Source newline interpretation follows the pinned GoogleSQL decoder.
      // This does not normalize a decoded \\r or a stored String value.
      ignore(self.advance())
      if self.peek() == Some(0x0a) {
        ignore(self.advance())
      }
      0x0a
    } else {
      self.advance()
    }
    if delimiter == 0x60 && (scalar == 0x0a || scalar == 0x0d) {
      raise LexicalAbort(InvalidScalar, self.byte_offset)
    }
    self.budget.charge(
      LiteralBytes,
      if scalar < 0x80 {
        1
      } else if scalar < 0x800 {
        2
      } else if scalar < 0x10000 {
        3
      } else {
        4
      },
      self.byte_offset,
    )
    output.write_char(scalar.unsafe_to_char())
  } nobreak {
    raise LexicalAbort(UnexpectedEnd, self.byte_offset)
  }
}

///|
fn digit(n : Int) -> Bool {
  n >= 0x30 && n <= 0x39
}

///|
fn Scanner::name(self : Scanner) -> String raise {
  let output = StringBuilder()
  while self.peek() is Some(n) && (identifier_start(n) || digit(n)) {
    self.budget.charge(LiteralBytes, 1, self.byte_offset)
    output.write_char(self.advance().unsafe_to_char())
  }
  output.to_string()
}

///|
// Keep the exact spelling until numeric admission; never round an integer
// token before checking the profile's exact-integer domain.
fn Scanner::number(self : Scanner) -> String raise {
  let start = self.byte_offset
  let output = StringBuilder()
  let mut count = 0
  while self.peek() is Some(n) && digit(n) {
    self.budget.charge(LiteralBytes, 1, self.byte_offset)
    output.write_char(self.advance().unsafe_to_char())
    count += 1
  }
  if self.peek() == Some(0x2e) {
    self.budget.charge(LiteralBytes, 1, self.byte_offset)
    output.write_char(self.advance().unsafe_to_char())
    while self.peek() is Some(n) && digit(n) {
      self.budget.charge(LiteralBytes, 1, self.byte_offset)
      output.write_char(self.advance().unsafe_to_char())
      count += 1
    }
  }
  if count == 0 {
    raise LexicalAbort(InvalidNumber, start)
  }
  if self.peek() == Some(0x65) || self.peek() == Some(0x45) {
    self.budget.charge(LiteralBytes, 1, self.byte_offset)
    output.write_char(self.advance().unsafe_to_char())
    if self.peek() == Some(0x2b) || self.peek() == Some(0x2d) {
      self.budget.charge(LiteralBytes, 1, self.byte_offset)
      output.write_char(self.advance().unsafe_to_char())
    }
    let mut digits = 0
    while self.peek() is Some(n) && digit(n) {
      self.budget.charge(LiteralBytes, 1, self.byte_offset)
      output.write_char(self.advance().unsafe_to_char())
      digits += 1
    }
    if digits == 0 {
      raise LexicalAbort(InvalidNumber, start)
    }
  }
  if self.peek() is Some(n) && (identifier_start(n) || n == 0x2e) {
    raise LexicalAbort(InvalidNumber, start)
  }
  output.to_string()
}

///|
fn Scanner::next(self : Scanner) -> Token raise {
  self.trivia()
  self.budget.charge(Tokens, 1, self.byte_offset)
  let start = self.byte_offset
  let mut annotation_compatible = false
  let value = match self.peek() {
    None => End
    Some(0x27) => {
      let (text, _) = self.quoted(0x27)
      Text(text)
    }
    Some(0x22) => {
      let (text, compatible) = self.quoted(0x22)
      annotation_compatible = compatible
      Text(text)
    }
    Some(0x60) => {
      let (text, _) = self.quoted(0x60)
      QuotedName(text)
    }
    Some(0x72 | 0x52) if self.peek(ahead=1) == Some(0x27) ||
      self.peek(ahead=1) == Some(0x22) => {
      ignore(self.advance())
      let delimiter = self.peek().unwrap()
      let (text, _) = self.quoted(delimiter, raw=true)
      Text(text)
    }
    Some(n) if identifier_start(n) => Word(self.name())
    Some(n) if digit(n) => Numeric(self.number())
    Some(0x2e) if self.peek(ahead=1) is Some(n) && digit(n) =>
      Numeric(self.number())
    Some(0x40) => {
      ignore(self.advance())
      if self.peek() is Some(n) && identifier_start(n) {
        Parameter(self.name())
      } else if self.peek() == Some(0x60) {
        let (text, _) = self.quoted(0x60)
        Parameter(text)
      } else {
        raise LexicalAbort(InvalidParameter, start)
      }
    }
    Some(0x7c) if self.peek(ahead=1) == Some(0x3e) => {
      ignore(self.advance())
      ignore(self.advance())
      Pipe
    }
    Some(0x7c) if self.peek(ahead=1) == Some(0x7c) => {
      ignore(self.advance())
      ignore(self.advance())
      Operator("||")
    }
    Some(0x3c | 0x3e | 0x21) => {
      let first = self.advance()
      let output = StringBuilder()
      output.write_char(first.unsafe_to_char())
      if self.peek() == Some(0x3d) ||
        (first == 0x3c && self.peek() == Some(0x3e)) {
        output.write_char(self.advance().unsafe_to_char())
      } else if first == 0x21 {
        raise LexicalAbort(UnexpectedToken, start)
      }
      Operator(output.to_string())
    }
    Some(
      0x28
      | 0x29
      | 0x2c
      | 0x2e
      | 0x3d
      | 0x3b
      | 0x2b
      | 0x2d
      | 0x2a
      | 0x2f
      | 0x25
      | 0x3a
      | 0x5b
      | 0x5d
      | 0x7b
      | 0x7d
    ) => Symbol(self.advance())
    _ => raise LexicalAbort(UnexpectedToken, start)
  }
  { value, start, end: self.byte_offset, annotation_compatible, }
}
