///|
fn valid_limits(limits : ParseLimits) -> Bool {
  // One-based end coordinates must fit Int even for an all-ASCII input line.
  limits.max_input_bytes >= 0 &&
  limits.max_input_bytes < 2147483647 &&
  limits.max_nodes >= 0 &&
  limits.max_depth >= 0
}

///|
fn input_error(
  issue : ParseIssue,
  source_path : String,
  location : ParseLocation,
) -> ParseError {
  { issue, source_path, location, path: None, }
}

///|
fn parse_admitted(
  source : String,
  source_path : String,
  limits : ParseLimits,
  yaml : Bool,
  normalize_text? : Bool = true,
) -> Result[ParsedSource, ParseError] {
  let parser = Parser::make(source, source_path, limits, normalize_text~)
  let node = try {
    if yaml {
      parser.yaml_document()
    } else {
      parser.document()
    }
  } catch {
    ParseAbort(error) => return Err(error)
  }
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
/// Both syntaxes share raw Unicode and byte admission before parsing.
fn parse_text_input(
  source : String,
  limits : ParseLimits,
  source_path : String,
  yaml : Bool,
) -> Result[ParsedSource, ParseError] {
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, source_path, Unavailable))
  }
  match @scalar.admit_utf8_length(source, limits.max_input_bytes) {
    Err(@scalar.Utf8AdmissionIssue::MalformedUtf16(offset)) =>
      return Err(input_error(InvalidUtf16, source_path, Utf16Offset(offset)))
    Err(_) => return Err(input_error(InputLimit, source_path, Unavailable))
    Ok(_) => ()
  }
  parse_admitted(source, source_path, limits, yaml)
}

///|
/// Strict UTF-8 decoding: no replacement characters are synthesized. Malformed
/// input reports the start of its first malformed sequence as a byte offset.
fn parse_bytes_input(
  source : Bytes,
  limits : ParseLimits,
  source_path : String,
  yaml : Bool,
  normalize_text? : Bool = true,
) -> Result[ParsedSource, ParseError] {
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, source_path, Unavailable))
  }
  if source.length() > limits.max_input_bytes {
    return Err(input_error(InputLimit, source_path, Unavailable))
  }
  let text = @utf8.decode(source[:], ignore_bom=false) catch {
    @utf8.Malformed(suffix) =>
      return Err(
        input_error(
          InvalidUtf8,
          source_path,
          ByteOffset(source.length() - suffix.length()),
        ),
      )
  }
  parse_admitted(text, source_path, limits, yaml, normalize_text~)
}

///|
/// Read bounded JSON, preserving decoded string values and normalizing object
/// keys to NFC then LF. Domain readers admit identifier-valued members.
pub fn parse_json(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
  parse_text_input(source, limits, source_path, false).map(parsed => parsed.node)
}

///|
/// Decode strict UTF-8 before JSON parsing, without replacement characters.
pub fn parse_json_bytes(
  source : Bytes,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
  parse_bytes_input(source, limits, source_path, false).map(parsed => {
    parsed.node
  })
}

///|
/// Decode strict bounded JSON without object-key normalization.
/// This preserves decoded external values and keys; consumers must perform
/// domain admission or an explicitly declared provider conversion.
pub fn parse_json_bytes_preserving(
  source : Bytes,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
  parse_bytes_input(source, limits, source_path, false, normalize_text=false).map(parsed => {
      parsed.node
    },
  )
}

///|
/// Read one restricted YAML Core document. Root shape and Program validation
/// belong to consumers. Tags, aliases and non-string keys are not admitted.
pub fn parse_yaml(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
  parse_text_input(source, limits, source_path, true).map(parsed => parsed.node)
}

///|
pub fn parse_yaml_bytes(
  source : Bytes,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
  parse_bytes_input(source, limits, source_path, true).map(parsed => parsed.node)
}

///|
pub fn parse_json_measured(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[ParsedSource, ParseError] {
  parse_text_input(source, limits, source_path, false)
}

///|
pub fn parse_yaml_measured(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[ParsedSource, ParseError] {
  parse_text_input(source, limits, source_path, true)
}

///|
pub fn parse_json_bytes_measured(
  source : Bytes,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[ParsedSource, ParseError] {
  parse_bytes_input(source, limits, source_path, false)
}

///|
pub fn parse_yaml_bytes_measured(
  source : Bytes,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[ParsedSource, ParseError] {
  parse_bytes_input(source, limits, source_path, true)
}
