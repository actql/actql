///|
pub(all) enum Mode {
  Parse
  Format
} derive(Eq, Debug)

///|
pub(all) enum Component {
  Token(String)
  Literal(String)
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_pattern_bytes : Int
  max_components : Int
  max_ast_bytes : Int
  max_ast_nodes : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  EmptyPattern
  InvalidComponent(Int)
  DuplicateToken(String)
  MissingDate
  InvalidTimeDependencies
} derive(Eq, Debug)

///|
struct Pattern {
  mode : Mode
  components : Array[Component]
  cid : String
  width : Int
  ast_bytes : Int
  ast_nodes : Int
}

///|
fn token_at(pattern : String, offset : Int) -> String? {
  for token in ["yyyy", "SSS", "MM", "dd", "HH", "mm", "ss"] {
    if token.length() > pattern.length() - offset {
      continue
    }
    let mut matches = true
    for i in 0..<token.length() {
      if pattern[offset + i] != token[i] {
        matches = false
        break
      }
    }
    if matches {
      return Some(token)
    }
  }
  None
}

///|
fn literal_at(pattern : String, offset : Int) -> String? {
  match pattern[offset].to_int() {
    0x2D => Some("-")
    0x2F => Some("/")
    0x3A => Some(":")
    0x20 => Some(" ")
    0x2E => Some(".")
    0x54 => Some("T")
    _ => None
  }
}

///|
fn emit_parts(
  mode : Mode,
  components : Array[Component],
  cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if cid is Some(cid) {
    @encode.key(writer, "ast_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "components")
  @encode.begin_array(writer)
  for component in components {
    let (kind, value) = match component {
      Token(value) => ("token", value)
      Literal(value) => ("literal", value)
    }
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, kind)
    @encode.key(writer, "value")
    @encode.string_value(writer, value)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "full_input_match")
  @encode.bool_value(writer, true)
  @encode.key(writer, "mode")
  @encode.string_value(writer, if mode == Parse { "parse" } else { "format" })
  @encode.key(writer, "timezone")
  @encode.string_value(writer, "UTC")
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-timestamp-pattern-ast/0.1")
  @encode.end_object(writer)
}

///|
/// Parse the pinned finite grammar without locale/timezone defaults or repair.
/// The admitted alphabet is ASCII, so accepted byte/scalar/code-unit lengths
/// coincide. Non-ASCII and isolated surrogates are rejected as components.
pub fn parse(
  pattern : String,
  mode : Mode,
  limits : Limits,
) -> Result[Pattern, Issue] {
  if limits.max_pattern_bytes < 0 ||
    limits.max_components < 0 ||
    limits.max_ast_bytes < 0 ||
    limits.max_ast_nodes < 0 {
    return Err(InvalidLimits)
  }
  if pattern.length() > limits.max_pattern_bytes {
    return Err(BudgetExceeded)
  }
  if pattern.is_empty() {
    return Err(EmptyPattern)
  }
  let components : Array[Component] = []
  let seen : Array[String] = []
  let mut offset = 0
  while offset < pattern.length() {
    if components.length() == limits.max_components {
      return Err(BudgetExceeded)
    }
    match token_at(pattern, offset) {
      Some(token) => {
        if seen.contains(token) {
          return Err(DuplicateToken(token))
        }
        seen.push(token)
        components.push(Token(token))
        offset += token.length()
      }
      None => {
        let literal = match literal_at(pattern, offset) {
          Some(v) => v
          None => return Err(InvalidComponent(offset))
        }
        components.push(Literal(literal))
        offset += 1
      }
    }
  }
  if mode == Parse &&
    (!seen.contains("yyyy") || !seen.contains("MM") || !seen.contains("dd")) {
    return Err(MissingDate)
  }
  if seen.contains("HH") != seen.contains("mm") ||
    (seen.contains("ss") && !seen.contains("HH")) ||
    (seen.contains("SSS") && !seen.contains("ss")) {
    return Err(InvalidTimeDependencies)
  }
  // Full wire AST has seven fixed nodes and three per component. Check before
  // multiplication so even caller-provided maximum Int limits cannot overflow.
  if limits.max_ast_nodes < 7 ||
    components.length() > (limits.max_ast_nodes - 7) / 3 {
    return Err(BudgetExceeded)
  }
  try {
    let hash = @encode.hashing_writer(
      limits.max_ast_bytes,
      limits.max_ast_nodes,
      3,
    )
    emit_parts(mode, components, None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let measure = @encode.measuring_writer(
      limits.max_ast_bytes,
      limits.max_ast_nodes,
      3,
    )
    emit_parts(mode, components, Some(cid), measure)
    let ast_bytes = @encode.finish_measurement(measure)
    Ok({
      mode,
      components,
      cid,
      width: pattern.length(),
      ast_bytes,
      ast_nodes: 7 + 3 * components.length(),
    })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn mode(v : Pattern) -> Mode {
  v.mode
}

///|
pub fn cid(v : Pattern) -> String {
  v.cid
}

///|
pub fn component_count(v : Pattern) -> Int {
  v.components.length()
}

///|
pub fn component_at(v : Pattern, index : Int) -> Component? {
  v.components.get(index)
}

///|
/// Exact ASCII value width: required parse input or non-null format output.
/// This is not proof that a particular input is a valid calendar value.
pub fn value_width(v : Pattern) -> Int {
  v.width
}

///|
/// Admitted pattern bytes, component count, full AST bytes and full AST nodes.
pub fn usage(v : Pattern) -> (Int, Int, Int, Int) {
  (v.width, v.components.length(), v.ast_bytes, v.ast_nodes)
}

///|
pub fn emit(
  v : Pattern,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_parts(v.mode, v.components, Some(v.cid), writer)
}

///|
pub fn emit_preimage(
  v : Pattern,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_parts(v.mode, v.components, None, writer)
}
