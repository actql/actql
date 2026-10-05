///|
/// Resumable admission in the existing source owner. Input Unicode/byte
/// preflight and grammar transitions report their work in the executing poll.
struct JsonParse {
  document : JsonDocument
  mut preflight_offset : Int
  mut preflight_bytes : Int
  mut preflight_done : Bool
  mut terminal : Bool
}

///|
pub(all) enum JsonParseControlIssue {
  InvalidQuantum
  Terminal
} derive(Eq, Debug)

///|
pub enum JsonParsePoll {
  JsonParseContinue(work~ : Int)
  JsonParseComplete(ParsedSource, work~ : Int)
  JsonParseFailed(ParseError, work~ : Int)
}

///|
pub fn start_json_parse(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[JsonParse, ParseError] {
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, source_path, Unavailable))
  }
  Ok({
    document: JsonDocument::make(Parser::make(source, source_path, limits)),
    preflight_offset: 0,
    preflight_bytes: 0,
    preflight_done: false,
    terminal: false,
  })
}

///|
fn json_preflight_step(cursor : JsonParse) -> ParseError? {
  let parser = cursor.document.parser
  let source = parser.source
  let index = cursor.preflight_offset
  if index >= source.length() {
    cursor.preflight_done = true
    return None
  }
  let first = source[index].to_int()
  let (units, bytes) = if first >= 0xd800 && first <= 0xdbff {
    if index + 1 >= source.length() ||
      source[index + 1].to_int() < 0xdc00 ||
      source[index + 1].to_int() > 0xdfff {
      return Some(
        input_error(InvalidUtf16, parser.source_path, Utf16Offset(index)),
      )
    }
    (2, 4)
  } else if first >= 0xdc00 && first <= 0xdfff {
    return Some(
      input_error(InvalidUtf16, parser.source_path, Utf16Offset(index)),
    )
  } else {
    (1, utf8_width(first))
  }
  if bytes > parser.limits.max_input_bytes - cursor.preflight_bytes {
    return Some(input_error(InputLimit, parser.source_path, Unavailable))
  }
  cursor.preflight_offset += units
  cursor.preflight_bytes += bytes
  None
}

///|
pub fn advance_json_parse(
  cursor : JsonParse,
  quantum : Int,
) -> Result[JsonParsePoll, JsonParseControlIssue] {
  if quantum < 1 {
    return Err(InvalidQuantum)
  }
  if cursor.terminal {
    return Err(Terminal)
  }
  let mut used = 0
  while used < quantum {
    used += 1
    if !cursor.preflight_done {
      if json_preflight_step(cursor) is Some(error) {
        cancel_json_parse(cursor)
        return Ok(JsonParseFailed(error, work=used))
      }
      continue
    }
    let node = cursor.document.step() catch {
      ParseAbort(error) => {
        cancel_json_parse(cursor)
        return Ok(JsonParseFailed(error, work=used))
      }
    }
    if node is Some(node) {
      let parser = cursor.document.parser
      let parsed : ParsedSource = {
        node,
        usage: {
          input_bytes: parser.byte_offset,
          nodes: parser.nodes,
          depth: parser.deepest,
        },
      }
      cancel_json_parse(cursor)
      return Ok(JsonParseComplete(parsed, work=used))
    }
  }
  Ok(JsonParseContinue(work=used))
}

///|
pub fn cancel_json_parse(cursor : JsonParse) -> Unit {
  cursor.document.frames.clear()
  cursor.document.parser.path.clear()
  cursor.document.completed = None
  cursor.document.parser.source = ""
  cursor.terminal = true
}
