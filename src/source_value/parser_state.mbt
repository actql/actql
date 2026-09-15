///|
priv struct Point {
  byte : Int
  line : Int
  column : Int
}

///|
priv struct Parser {
  source : String
  source_path : String
  limits : ParseLimits
  path : Array[PathSegment]
  mut offset : Int
  mut byte_offset : Int
  mut line : Int
  mut column : Int
  mut nodes : Int
  mut deepest : Int
}

///|
fn Parser::make(
  source : String,
  source_path : String,
  limits : ParseLimits,
) -> Parser {
  let bom = source.length() > 0 && source[0].to_int() == 0xfeff
  {
    source,
    source_path,
    limits,
    path: [],
    offset: if bom {
      1
    } else {
      0
    },
    byte_offset: if bom {
      3
    } else {
      0
    },
    line: 1,
    column: 1,
    nodes: 0,
    deepest: 0,
  }
}

///|
fn Parser::point(self : Parser) -> Point {
  { byte: self.byte_offset, line: self.line, column: self.column, }
}

///|
fn Parser::span(self : Parser, start : Point) -> Span {
  {
    start_byte: start.byte,
    end_byte: self.byte_offset,
    start_line: start.line,
    start_column: start.column,
    end_line: self.line,
    end_column: self.column,
    source_path: self.source_path,
  }
}

///|
fn Parser::failure_at(
  self : Parser,
  issue : ParseIssue,
  path : Array[PathSegment],
  start : Point,
) -> ParseAbort {
  ParseAbort({
    issue,
    source_path: self.source_path,
    location: Source(self.span(start)),
    path: Some(path.copy()),
  })
}

///|
fn[T] Parser::fail(
  self : Parser,
  issue : ParseIssue,
  path : Array[PathSegment],
) -> T raise ParseAbort {
  raise self.failure_at(issue, path, self.point())
}

///|
fn utf8_width(scalar : Int) -> Int {
  if scalar <= 0x7f {
    1
  } else if scalar <= 0x7ff {
    2
  } else if scalar <= 0xffff {
    3
  } else {
    4
  }
}

///|
/// Preflight has already established well-formed UTF-16 and bounded byte length.
fn Parser::advance_scalar(
  self : Parser,
  path : Array[PathSegment],
) -> Int raise ParseAbort {
  if self.offset >= self.source.length() {
    self.fail(UnexpectedEnd, path)
  }
  let first = self.source[self.offset].to_int()
  if first >= 0xd800 && first <= 0xdbff {
    let low = self.source[self.offset + 1].to_int()
    let scalar = 0x10000 + ((first - 0xd800) << 10) + low - 0xdc00
    self.offset += 2
    self.byte_offset += 4
    self.column += 1
    return scalar
  }
  self.offset += 1
  self.byte_offset += utf8_width(first)
  if first == 0x0a {
    if self.offset < 2 || self.source[self.offset - 2].to_int() != 0x0d {
      self.line += 1
    }
    self.column = 1
  } else if first == 0x0d {
    self.line += 1
    self.column = 1
  } else {
    self.column += 1
  }
  first
}

///|
fn Parser::peek(self : Parser) -> Int? {
  if self.offset < self.source.length() {
    Some(self.source[self.offset].to_int())
  } else {
    None
  }
}

///|
fn Parser::skip_space(self : Parser) -> Unit raise ParseAbort {
  while self.peek() is Some(unit) &&
        (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) {
    ignore(self.advance_scalar(self.path))
  }
}
