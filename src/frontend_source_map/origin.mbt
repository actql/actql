///|
/// Coordinates refer to original input, before semantic normalization.
pub(all) struct Position {
  byte_offset : Int
  scalar_offset : Int
  utf16_offset : Int
  line : Int
  scalar_column : Int
  utf16_column : Int
} derive(Eq, Debug)

///|
pub(all) enum Kind {
  Authored
  Generated
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimit
  InputLimit
  InvalidUnicode
  InvalidUtf8
  InvalidRange
  InvalidSpan
} derive(Eq, Debug)

///|
struct Document {
  identity : Ref[Unit]
  path : String
  positions : Array[Position]
  bytes : Int
}

///|
struct Origin {
  owner : Ref[Unit]
  span : @span.Span
  start : Position
  end : Position
  kind : Kind
}

///|
/// Bound the original bytes before allocating the scalar-boundary index.
pub fn document(
  text : String,
  max_bytes : Int,
  source_path? : String = "<generated>",
) -> Result[Document, Issue] {
  if max_bytes < 0 || max_bytes == 2147483647 {
    return Err(InvalidLimit)
  }
  let bytes = match @scalar.admit_utf8_length(text, max_bytes) {
    Ok(n) => n
    Err(@scalar.MalformedUtf16(_)) => return Err(InvalidUnicode)
    Err(_) => return Err(InputLimit)
  }
  let positions : Array[Position] = []
  let mut i = 0
  let mut byte_offset = 0
  let mut scalar_offset = 0
  let mut line = 1
  let mut scalar_column = 1
  let mut utf16_column = 1
  while true {
    positions.push({
      byte_offset,
      scalar_offset,
      utf16_offset: i,
      line,
      scalar_column,
      utf16_column,
    })
    if i == text.length() {
      break
    }
    let unit = text[i].to_int()
    let width = if unit >= 0xd800 && unit <= 0xdbff { 2 } else { 1 }
    byte_offset += if width == 2 {
      4
    } else if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else {
      3
    }
    scalar_offset += 1
    if unit == 0xfeff && i == 0 {
      // Match the existing source parser's leading-BOM coordinates.
      ()
    } else if unit == 0x0d {
      line += 1
      scalar_column = 1
      utf16_column = 1
    } else if unit == 0x0a {
      if i == 0 || text[i - 1].to_int() != 0x0d {
        line += 1
      }
      scalar_column = 1
      utf16_column = 1
    } else {
      scalar_column += 1
      utf16_column += width
    }
    i += width
  }
  Ok({ identity: Ref(()), path: source_path, positions, bytes, })
}

///|
pub fn document_bytes(
  bytes : Bytes,
  max_bytes : Int,
  source_path? : String = "<generated>",
) -> Result[Document, Issue] {
  if max_bytes < 0 || max_bytes == 2147483647 {
    return Err(InvalidLimit)
  }
  if bytes.length() > max_bytes {
    return Err(InputLimit)
  }
  let text = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => return Err(InvalidUtf8)
  }
  document(text, max_bytes, source_path~)
}

///|
pub fn input_bytes(source : Document) -> Int {
  source.bytes
}

///|
pub fn position(source : Document, byte_offset : Int) -> Position? {
  let mut lo = 0
  let mut hi = source.positions.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let p = source.positions[mid]
    if p.byte_offset < byte_offset {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < source.positions.length() &&
    source.positions[lo].byte_offset == byte_offset {
    Some(source.positions[lo])
  } else {
    None
  }
}

///|
pub fn range(
  source : Document,
  start_byte : Int,
  end_byte : Int,
  kind? : Kind = Authored,
) -> Result[Origin, Issue] {
  if end_byte < start_byte {
    return Err(InvalidRange)
  }
  let start = match position(source, start_byte) {
    Some(p) => p
    None => return Err(InvalidRange)
  }
  let end = match position(source, end_byte) {
    Some(p) => p
    None => return Err(InvalidRange)
  }
  Ok({
    owner: source.identity,
    start,
    end,
    kind,
    span: {
      start_byte,
      end_byte,
      start_line: start.line,
      start_column: start.scalar_column,
      end_line: end.line,
      end_column: end.scalar_column,
      source_path: source.path,
    },
  })
}

///|
pub fn validate_span(
  source : Document,
  span : @span.Span,
  kind? : Kind = Authored,
) -> Result[Origin, Issue] {
  match range(source, span.start_byte, span.end_byte, kind~) {
    Ok(origin) if origin.span == span => Ok(origin)
    _ => Err(InvalidSpan)
  }
}

///|
pub fn belongs_to(source : Document, origin : Origin) -> Bool {
  physical_equal(source.identity, origin.owner)
}

///|
pub fn span(origin : Origin) -> @span.Span {
  origin.span
}

///|
pub fn start(origin : Origin) -> Position {
  origin.start
}

///|
pub fn end(origin : Origin) -> Position {
  origin.end
}

///|
pub fn kind(origin : Origin) -> Kind {
  origin.kind
}
