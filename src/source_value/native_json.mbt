///|
/// Fixed Host representation projections for already captured JSON DATA.
/// They provide values, never claimed measurements or admission evidence.
/// No Resource/current/permission operation is available through this view.
pub(all) struct JsonDataReader[T] {
  kind : (T) -> Int
  boolean : (T) -> Bool
  number_text : (T) -> String
  text : (T) -> String
  keys : (T) -> FixedArray[String]
  length : (T) -> Int
  field : (T, String) -> T
}

///|
priv enum NativeJsonFrame[T] {
  NativeArray(T, Int, Array[Node])
  NativeObject(
    T,
    FixedArray[String],
    Array[Field],
    @shape.KeyAdmission,
    Ref[(String, Span)?]
  )
}

///|
// Count the native JSON representation without constructing another wire.
// Normalization belongs to the original source owner after this measurement.
fn native_json_string_shape(text : String) -> (Int64, Int64)? {
  let mut bytes = 2L
  let mut columns = 2L
  let mut index = 0
  while index < text.length() {
    let unit = text[index].to_int()
    if unit >= 0xd800 && unit <= 0xdbff {
      if index + 1 >= text.length() ||
        text[index + 1].to_int() < 0xdc00 ||
        text[index + 1].to_int() > 0xdfff {
        return None
      }
      bytes += 4L
      columns += 1L
      index += 2
      continue
    }
    if unit >= 0xdc00 && unit <= 0xdfff {
      return None
    }
    if unit == 0x22 ||
      unit == 0x5c ||
      unit == 8 ||
      unit == 9 ||
      unit == 10 ||
      unit == 12 ||
      unit == 13 {
      bytes += 2L
      columns += 2L
    } else if unit < 0x20 {
      bytes += 6L
      columns += 6L
    } else {
      bytes += utf8_width(unit).to_int64()
      columns += 1L
    }
    index += 1
  }
  Some((bytes, columns))
}

///|
/// Construct the existing source tree from the SDK-owned detached native
/// value. There is no whole-input JSON.stringify/parse, recursive JS walker or invented
/// MoonBit representation. The original source owner retains key laws and
/// measures nodes/depth/bytes while constructing; editable DATA is not proof.
/// Native objects have no authored text coordinates. When normalized keys
/// are selected, key spans retain only their scalar position in this same
/// detached value's compact JSON representation. They supply no location
/// without the separately retained matching representation; Node spans remain
/// unavailable.
pub fn[T] admit_captured_json(
  input : T,
  reader : JsonDataReader[T],
  limits : ParseLimits,
  program_keys? : Bool = false,
  normalize_keys? : Bool = false,
  source_path? : String = "<snapshot>",
) -> Result[ParsedSource, ParseError] {
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, source_path, Unavailable))
  }
  let span : Span = {
    start_byte: 0,
    end_byte: 0,
    start_line: 1,
    end_line: 1,
    start_column: 1,
    end_column: 1,
    source_path,
  }
  let frames : Array[NativeJsonFrame[T]] = []
  let path : Array[PathSegment] = []
  let mut current = input
  let mut completed : Node? = None
  let mut nodes = 0
  let mut deepest = 0
  let mut bytes = 0L
  let mut key_offset = 0L
  let mut key_column = 1L
  fn failure(issue : ParseIssue) -> Result[ParsedSource, ParseError] {
    Err({ issue, source_path, location: Unavailable, path: Some(path.copy()), })
  }
  while true {
    if completed is None {
      if nodes >= limits.max_nodes {
        return failure(NodeLimit)
      }
      nodes += 1
      let kind = (reader.kind)(current)
      if kind == 4 || kind == 5 {
        if frames.length() >= limits.max_depth {
          return failure(DepthLimit)
        }
        deepest = Int::max(deepest, frames.length() + 1)
      }
      let value : Value = match kind {
        0 => {
          bytes += 4L
          key_offset += 4L
          key_column += 4L
          Null
        }
        1 => {
          let value = (reader.boolean)(current)
          bytes += if value { 4L } else { 5L }
          key_offset += if value { 4L } else { 5L }
          key_column += if value { 4L } else { 5L }
          Bool(value)
        }
        2 => {
          // One ordinary scalar-domain conversion, not another whole-input
          // serializer/parser. The fixed Host reader supplies native Number's
          // shortest spelling. No claimed byte count or admitted Bool enters.
          let spelling = (reader.number_text)(current)
          let parsed = match
            parse_json_measured(spelling, {
              ..limits,
              max_nodes: 1,
              max_depth: 0,
            }) {
            Err(issue) => return failure(issue.issue)
            Ok(value) => value
          }
          guard parsed.node.value is Number(value) else {
            return failure(InvalidNumber)
          }
          bytes += parsed.usage.input_bytes.to_int64()
          key_offset += parsed.usage.input_bytes.to_int64()
          key_column += parsed.usage.input_bytes.to_int64()
          Number(value)
        }
        3 => {
          let text = (reader.text)(current)
          guard native_json_string_shape(text) is Some((size, columns)) else {
            return failure(InvalidUnicodeEscape)
          }
          bytes += size
          key_offset += size
          key_column += columns
          String(text)
        }
        4 => {
          bytes += 2L
          key_offset += 1L
          key_column += 1L
          let count = (reader.length)(current)
          if count < 0 || count > limits.max_nodes - nodes {
            return failure(NodeLimit)
          }
          if count > 0 {
            bytes += (count - 1).to_int64()
          }
          let items : Array[Node] = []
          frames.push(NativeArray(current, count, items))
          Array(items)
        }
        5 => {
          bytes += 2L
          key_offset += 1L
          key_column += 1L
          let keys = (reader.keys)(current)
          if keys.length() > limits.max_nodes - nodes {
            return failure(NodeLimit)
          }
          if keys.length() > 0 {
            bytes += (keys.length() - 1).to_int64()
          }
          let fields : Array[Field] = []
          frames.push(
            NativeObject(
              current,
              keys,
              fields,
              @shape.key_admission(),
              Ref(None),
            ),
          )
          Object(fields)
        }
        _ => return failure(UnexpectedToken)
      }
      if bytes > limits.max_input_bytes.to_int64() {
        return failure(InputLimit)
      }
      if kind != 4 && kind != 5 {
        completed = Some({ value, span, })
      }
    }
    if completed is Some(node) {
      if frames.length() == 0 {
        return Ok({
          node,
          usage: { input_bytes: bytes.to_int(), nodes, depth: deepest, },
        })
      }
      match frames[frames.length() - 1] {
        NativeArray(_, _, items) => items.push(node)
        NativeObject(_, _, fields, _, pending_key) => {
          guard pending_key.val is Some((key, key_span)) else {
            return failure(UnexpectedToken)
          }
          fields.push({ key, key_span, value: node, })
        }
      }
      ignore(path.pop())
      completed = None
    }
    match frames[frames.length() - 1] {
      NativeArray(original, count, items) =>
        if items.length() == count {
          ignore(frames.pop())
          key_offset += 1L
          key_column += 1L
          completed = Some({ value: Array(items), span, })
        } else {
          let index = items.length()
          if index > 0 {
            key_offset += 1L
            key_column += 1L
          }
          path.push(Index(index))
          current = (reader.field)(original, index.to_string())
        }
      NativeObject(original, keys, fields, seen, pending_key) =>
        if fields.length() == keys.length() {
          ignore(frames.pop())
          key_offset += 1L
          key_column += 1L
          completed = Some({ value: Object(fields), span, })
        } else {
          let raw = keys[fields.length()]
          guard native_json_string_shape(raw) is Some((size, columns)) else {
            return failure(InvalidUnicodeEscape)
          }
          bytes += size + 1L
          if bytes > limits.max_input_bytes.to_int64() {
            return failure(InputLimit)
          }
          let key = if source_normalizes_key(
              program_keys || normalize_keys,
              program_keys,
              path,
            ) {
            match @canonical.normalize_nfc_lf(raw) {
              Ok(value) => value
              Err(_) => return failure(InvalidUnicodeEscape)
            }
          } else {
            raw
          }
          path.push(Key(key))
          if !@shape.admit_key(seen, key) {
            return failure(DuplicateKey(key))
          }
          if fields.length() > 0 {
            key_offset += 1L
            key_column += 1L
          }
          let start = key_offset
          let start_column = key_column
          key_offset += size
          key_column += columns
          let key_span = if normalize_keys {
            {
              ..span,
              start_byte: start.to_int(),
              end_byte: key_offset.to_int(),
              start_column: start_column.to_int(),
              end_column: key_column.to_int(),
              source_path: "<captured-json>",
            }
          } else {
            span
          }
          key_offset += 1L // The same member's colon.
          key_column += 1L
          pending_key.val = Some((key, key_span))
          current = (reader.field)(original, raw)
        }
    }
  } nobreak {
    failure(UnexpectedEnd)
  }
}
