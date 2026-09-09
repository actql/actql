///|
fn valid_limits(limits : JsonLimits) -> Bool {
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
  limits : JsonLimits,
) -> Result[Node, ParseError] {
  Ok(Parser::make(source, source_path, limits).document()) catch {
    ParseAbort(error) => Err(error)
  }
}

///|
/// Read one JSON value, normalizing strings and keys with NFC then LF. Input
/// limits apply before normalization, including whitespace and a leading BOM.
/// Returned arrays are editable syntax data, not an admission proof.
pub fn parse_json(
  source : String,
  limits : JsonLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, source_path, Unavailable))
  }
  match @scalar.admit_utf8_length(source, limits.max_input_bytes) {
    Err(@scalar.Utf8AdmissionIssue::MalformedUtf16(offset)) =>
      return Err(input_error(InvalidUtf16, source_path, Utf16Offset(offset)))
    Err(_) => return Err(input_error(InputLimit, source_path, Unavailable))
    Ok(_) => ()
  }
  parse_admitted(source, source_path, limits)
}

///|
/// Strict UTF-8 decoding: no replacement characters are synthesized. Malformed
/// input reports the start of its first malformed sequence as a byte offset.
pub fn parse_json_bytes(
  source : Bytes,
  limits : JsonLimits,
  source_path? : String = "<memory>",
) -> Result[Node, ParseError] {
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
  parse_admitted(text, source_path, limits)
}
