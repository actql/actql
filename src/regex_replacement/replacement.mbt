///|
pub(all) enum Part {
  Literal(String)
  Capture(Int)
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_input_bytes : Int
  max_parts : Int
  max_ast_bytes : Int
  max_ast_nodes : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidUnicode(Int)
  NonCanonicalText
  InvalidReplacement(Int)
} derive(Eq, Debug)

///|
pub struct Stats {
  literal_utf8_bytes : Int
  capture_reference_count : Int
  max_capture_index : Int
} derive(Eq, Debug)

///|
struct Replacement {
  parts : Array[Part]
  stats : Stats
  cid : String
  input_bytes : Int
  ast_bytes : Int
  ast_nodes : Int
}

///|
fn emit_parts(
  parts : Array[Part],
  stats : Stats,
  cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if cid is Some(cid) {
    @encode.key(writer, "ast_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "capture_reference_count")
  @encode.number_value(writer, stats.capture_reference_count.to_double())
  @encode.key(writer, "literal_utf8_bytes")
  @encode.number_value(writer, stats.literal_utf8_bytes.to_double())
  @encode.key(writer, "max_capture_index")
  @encode.number_value(writer, stats.max_capture_index.to_double())
  @encode.key(writer, "parts")
  @encode.begin_array(writer)
  for part in parts {
    @encode.begin_object(writer)
    match part {
      Literal(value) => {
        @encode.key(writer, "kind")
        @encode.string_value(writer, "literal")
        @encode.key(writer, "value")
        @encode.string_value(writer, value)
      }
      Capture(index) => {
        @encode.key(writer, "capture")
        @encode.number_value(writer, index.to_double())
        @encode.key(writer, "kind")
        @encode.string_value(writer, "capture")
      }
    }
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-regex-replacement-ast/0.1")
  @encode.end_object(writer)
}

///|
/// Parse canonical replacement text, not Host replacement syntax. Capture
/// existence must be checked against the associated admitted regex separately.
pub fn parse(text : String, limits : Limits) -> Result[Replacement, Issue] {
  if limits.max_input_bytes < 0 ||
    limits.max_parts < 0 ||
    limits.max_ast_bytes < 0 ||
    limits.max_ast_nodes < 0 {
    return Err(InvalidLimits)
  }
  let input_bytes = match
    @scalar.admit_utf8_length(text, limits.max_input_bytes) {
    Ok(v) => v
    Err(@scalar.MalformedUtf16(offset)) => return Err(InvalidUnicode(offset))
    Err(_) => return Err(BudgetExceeded)
  }
  match @canonical.normalize_nfc_lf(text) {
    Ok(value) if value == text => ()
    Ok(_) => return Err(NonCanonicalText)
    Err(@canonical.UnpairedSurrogate(offset)) =>
      return Err(InvalidUnicode(offset))
  }
  let parts : Array[Part] = []
  let mut literal = StringBuilder()
  let mut has_literal = false
  let mut literal_bytes = input_bytes
  let mut captures = 0
  let mut maximum = 0
  let mut offset = 0
  while offset < text.length() {
    let unit = text[offset].to_int()
    if unit != 0x24 {
      // UTF-16 has already been validated without replacement above.
      let cp = if unit >= 0xD800 && unit <= 0xDBFF {
        let low = text[offset + 1].to_int()
        offset += 2
        0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00
      } else {
        offset += 1
        unit
      }
      literal.write_char(cp.unsafe_to_char())
      has_literal = true
      continue
    }
    if offset + 1 < text.length() && text[offset + 1].to_int() == 0x24 {
      literal.write_char('$')
      has_literal = true
      literal_bytes -= 1
      offset += 2
      continue
    }
    if offset + 1 == text.length() {
      return Err(InvalidReplacement(offset))
    }
    let first = text[offset + 1].to_int()
    if first < 0x31 || first > 0x39 {
      return Err(InvalidReplacement(offset))
    }
    let mut capture = first - 0x30
    let mut consumed = 2
    if text.length() - offset > 2 {
      let second = text[offset + 2].to_int()
      if second >= 0x30 && second <= 0x39 {
        capture = capture * 10 + second - 0x30
        consumed = 3
      }
    }
    if has_literal {
      if parts.length() == limits.max_parts {
        return Err(BudgetExceeded)
      }
      parts.push(Literal(literal.to_string()))
      literal = StringBuilder()
      has_literal = false
    }
    if parts.length() == limits.max_parts {
      return Err(BudgetExceeded)
    }
    parts.push(Capture(capture))
    captures += 1
    maximum = Int::max(maximum, capture)
    literal_bytes -= consumed
    offset += consumed
  }
  if has_literal {
    if parts.length() == limits.max_parts {
      return Err(BudgetExceeded)
    }
    parts.push(Literal(literal.to_string()))
  }
  let stats : Stats = {
    literal_utf8_bytes: literal_bytes,
    capture_reference_count: captures,
    max_capture_index: maximum,
  }
  if limits.max_ast_nodes < 7 || parts.length() > (limits.max_ast_nodes - 7) / 3 {
    return Err(BudgetExceeded)
  }
  try {
    let hash = @encode.hashing_writer(
      limits.max_ast_bytes,
      limits.max_ast_nodes,
      3,
    )
    emit_parts(parts, stats, None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let measure = @encode.measuring_writer(
      limits.max_ast_bytes,
      limits.max_ast_nodes,
      3,
    )
    emit_parts(parts, stats, Some(cid), measure)
    let ast_bytes = @encode.finish_measurement(measure)
    Ok({
      parts,
      stats,
      cid,
      input_bytes,
      ast_bytes,
      ast_nodes: 7 + 3 * parts.length(),
    })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn cid(v : Replacement) -> String {
  v.cid
}

///|
pub fn stats(v : Replacement) -> Stats {
  v.stats
}

///|
pub fn part_count(v : Replacement) -> Int {
  v.parts.length()
}

///|
pub fn part_at(v : Replacement, index : Int) -> Part? {
  v.parts.get(index)
}

///|
/// Original replacement UTF-8 bytes, full AST bytes and full AST nodes.
pub fn usage(v : Replacement) -> (Int, Int, Int) {
  (v.input_bytes, v.ast_bytes, v.ast_nodes)
}

///|
pub fn emit(
  v : Replacement,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_parts(v.parts, v.stats, Some(v.cid), writer)
}

///|
pub fn emit_preimage(
  v : Replacement,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_parts(v.parts, v.stats, None, writer)
}
