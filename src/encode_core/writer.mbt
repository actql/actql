///|
/// Stateful bounded JSON emission. A failed operation closes the writer.
/// Errors are typed; partial output is never available through finalization.
pub(all) suberror EncodeFailure {
  InvalidStructure
  InvalidUnicode
  InvalidNumber
  OutputLimit
  ClosedWriter
} derive(Debug)

///|
priv enum Frame {
  ArrayItems(Bool)
  ObjectKey(Bool, Map[String, Unit])
  ObjectValue(Map[String, Unit])
}

///|
priv enum OutputSink {
  TextOutput(StringBuilder)
  MeasureOutput
  HashOutput(@sha256.Hasher)
}

///|
struct Writer {
  output : OutputSink
  frames : Array[Frame]
  max_bytes : Int
  max_nodes : Int
  mut peak_depth : Int
  mut remaining_bytes : Int
  mut remaining_nodes : Int
  max_depth : Int
  mut root_written : Bool
  mut closed : Bool
}

///|
/// Caller-provided UTF-8 byte, value-node and open-container depth limits.
/// Scalar roots have depth zero; object keys are not separate value nodes.
pub fn writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Writer raise EncodeFailure {
  create_writer(max_bytes, max_nodes, max_depth, TextOutput(StringBuilder()))
}

///|
/// Same admission, escaping and budget rules; no output text is retained.
pub fn measuring_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Writer raise EncodeFailure {
  create_writer(max_bytes, max_nodes, max_depth, MeasureOutput)
}

///|
fn create_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  output : OutputSink,
) -> Writer raise EncodeFailure {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    raise OutputLimit
  }
  {
    output,
    frames: [],
    max_bytes,
    max_nodes,
    peak_depth: 0,
    remaining_bytes: max_bytes,
    remaining_nodes: max_nodes,
    max_depth,
    root_written: false,
    closed: false,
  }
}

///|
/// Hash the same bounded UTF-8 stream without retaining serialized output.
pub fn hashing_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Writer raise EncodeFailure {
  create_writer(max_bytes, max_nodes, max_depth, HashOutput(@sha256.hasher()))
}

///|
fn hash_byte(
  w : Writer,
  h : @sha256.Hasher,
  byte : Int,
) -> Unit raise EncodeFailure {
  @sha256.update_byte(h, byte.to_byte()) catch {
    @sha256.ClosedHasher => fail(w, ClosedWriter)
    @sha256.MessageTooLong => fail(w, OutputLimit)
  }
}

///|
fn hash_scalar(
  w : Writer,
  h : @sha256.Hasher,
  scalar : Int,
) -> Unit raise EncodeFailure {
  if scalar < 128 {
    hash_byte(w, h, scalar)
  } else if scalar < 2048 {
    hash_byte(w, h, 0xc0 | (scalar >> 6))
    hash_byte(w, h, 0x80 | (scalar & 63))
  } else if scalar < 65536 {
    hash_byte(w, h, 0xe0 | (scalar >> 12))
    hash_byte(w, h, 0x80 | ((scalar >> 6) & 63))
    hash_byte(w, h, 0x80 | (scalar & 63))
  } else {
    hash_byte(w, h, 0xf0 | (scalar >> 18))
    hash_byte(w, h, 0x80 | ((scalar >> 12) & 63))
    hash_byte(w, h, 0x80 | ((scalar >> 6) & 63))
    hash_byte(w, h, 0x80 | (scalar & 63))
  }
}

///|
fn[T] fail(w : Writer, error : EncodeFailure) -> T raise EncodeFailure {
  w.closed = true
  raise error
}

///|
fn active(w : Writer) -> Unit raise EncodeFailure {
  if w.closed {
    raise ClosedWriter
  }
}

///|
fn ascii(w : Writer, text : String) -> Unit raise EncodeFailure {
  if text.length() > w.remaining_bytes {
    fail(w, OutputLimit)
  }
  w.remaining_bytes -= text.length()
  match w.output {
    TextOutput(output) => output.write_string(text)
    MeasureOutput => ()
    HashOutput(h) =>
      for unit in text {
        hash_byte(w, h, unit.to_int())
      }
  }
}

///|
fn quoted(w : Writer, text : String) -> Unit raise EncodeFailure {
  ascii(w, "\"")
  let mut i = 0
  while i < text.length() {
    let unit = text[i].to_int()
    match unit {
      0x22 => ascii(w, "\\\"")
      0x5c => ascii(w, "\\\\")
      8 => ascii(w, "\\b")
      12 => ascii(w, "\\f")
      10 => ascii(w, "\\n")
      13 => ascii(w, "\\r")
      9 => ascii(w, "\\t")
      _ if unit < 32 => {
        let digits = "0123456789abcdef"
        ascii(w, "\\u00")
        ascii(w, digits[(unit >> 4) & 15].to_int().unsafe_to_char().to_string())
        ascii(w, digits[unit & 15].to_int().unsafe_to_char().to_string())
      }
      _ => {
        let scalar = if unit >= 0xd800 && unit <= 0xdbff {
          if i + 1 >= text.length() {
            fail(w, InvalidUnicode)
          }
          let low = text[i + 1].to_int()
          if low < 0xdc00 || low > 0xdfff {
            fail(w, InvalidUnicode)
          }
          i += 1
          0x10000 + ((unit - 0xd800) << 10) + low - 0xdc00
        } else if unit >= 0xdc00 && unit <= 0xdfff {
          fail(w, InvalidUnicode)
        } else {
          unit
        }
        let bytes = if scalar < 128 {
          1
        } else if scalar < 2048 {
          2
        } else if scalar < 65536 {
          3
        } else {
          4
        }
        if bytes > w.remaining_bytes {
          fail(w, OutputLimit)
        }
        w.remaining_bytes -= bytes
        match w.output {
          TextOutput(output) => output.write_char(scalar.unsafe_to_char())
          MeasureOutput => ()
          HashOutput(h) => hash_scalar(w, h, scalar)
        }
      }
    }
    i += 1
  }
  ascii(w, "\"")
}

///|
fn value_start(w : Writer) -> Unit raise EncodeFailure {
  active(w)
  if w.remaining_nodes <= 0 {
    fail(w, OutputLimit)
  }
  if w.frames.is_empty() {
    if w.root_written {
      fail(w, InvalidStructure)
    }
    w.root_written = true
  } else {
    let index = w.frames.length() - 1
    match w.frames[index] {
      ArrayItems(first) => {
        if !first {
          ascii(w, ",")
        }
        w.frames[index] = ArrayItems(false)
      }
      ObjectKey(_, _) => fail(w, InvalidStructure)
      ObjectValue(keys) => w.frames[index] = ObjectKey(false, keys)
    }
  }
  w.remaining_nodes -= 1
}

///|
pub fn null_value(w : Writer) -> Unit raise EncodeFailure {
  value_start(w)
  ascii(w, "null")
}

///|
pub fn bool_value(w : Writer, value : Bool) -> Unit raise EncodeFailure {
  value_start(w)
  ascii(w, if value { "true" } else { "false" })
}

///|
/// Finite binary64 spelling only; NaN, infinities and negative zero are rejected.
pub fn number_value(w : Writer, value : Double) -> Unit raise EncodeFailure {
  active(w)
  if value.is_nan() ||
    value.is_inf() ||
    value.reinterpret_as_uint64() == 0x8000000000000000UL {
    fail(w, InvalidNumber)
  }
  value_start(w)
  ascii(w, value.to_string())
}

///|
/// Escapes without normalization. Unpaired UTF-16 surrogates are rejected.
pub fn string_value(w : Writer, value : String) -> Unit raise EncodeFailure {
  value_start(w)
  quoted(w, value)
}

///|
pub fn begin_array(w : Writer) -> Unit raise EncodeFailure {
  value_start(w)
  if w.frames.length() >= w.max_depth {
    fail(w, OutputLimit)
  }
  ascii(w, "[")
  w.frames.push(ArrayItems(true))
  w.peak_depth = w.peak_depth.max(w.frames.length())
}

///|
pub fn begin_object(w : Writer) -> Unit raise EncodeFailure {
  value_start(w)
  if w.frames.length() >= w.max_depth {
    fail(w, OutputLimit)
  }
  ascii(w, "{")
  w.frames.push(ObjectKey(true, Map([])))
  w.peak_depth = w.peak_depth.max(w.frames.length())
}

///|
pub fn key(w : Writer, name : String) -> Unit raise EncodeFailure {
  active(w)
  if w.frames.is_empty() {
    fail(w, InvalidStructure)
  }
  let index = w.frames.length() - 1
  match w.frames[index] {
    ObjectKey(first, keys) => {
      // Every UTF16 unit requires at least one emitted byte. Reject oversized
      // names before Map hashing scans caller-owned text. Exact escaping and
      // punctuation accounting still happens in quoted/ascii below.
      if name.length() > w.remaining_bytes {
        fail(w, OutputLimit)
      }
      if keys.contains(name) {
        fail(w, InvalidStructure)
      }
      if !first {
        ascii(w, ",")
      }
      quoted(w, name)
      ascii(w, ":")
      keys[name] = ()
      w.frames[index] = ObjectValue(keys)
    }
    ArrayItems(_) | ObjectValue(_) => fail(w, InvalidStructure)
  }
}

///|
pub fn end_array(w : Writer) -> Unit raise EncodeFailure {
  active(w)
  match w.frames.last() {
    Some(ArrayItems(_)) => {
      ignore(w.frames.pop())
      ascii(w, "]")
    }
    Some(ObjectKey(_, _)) | Some(ObjectValue(_)) | None =>
      fail(w, InvalidStructure)
  }
}

///|
pub fn end_object(w : Writer) -> Unit raise EncodeFailure {
  active(w)
  match w.frames.last() {
    Some(ObjectKey(_, _)) => {
      ignore(w.frames.pop())
      ascii(w, "}")
    }
    Some(ArrayItems(_)) | Some(ObjectValue(_)) | None =>
      fail(w, InvalidStructure)
  }
}

///|
pub fn finish(w : Writer) -> String raise EncodeFailure {
  active(w)
  guard w.output is TextOutput(output) else { fail(w, InvalidStructure) }
  finish_state(w)
  output.to_string()
}

///|
/// Close a complete measured value and return its exact UTF-8 byte length.
/// A measurement cannot be promoted to EncodedDocument or read as text.
pub fn finish_measurement(w : Writer) -> Int raise EncodeFailure {
  finish_measurement_usage(w).0
}

///|
/// Complete one measured value, returning (UTF-8 bytes, value nodes, peak
/// open-container depth). No text is retained or second traversal performed.
pub fn finish_measurement_usage(
  w : Writer,
) -> (Int, Int, Int) raise EncodeFailure {
  active(w)
  guard w.output is MeasureOutput else { fail(w, InvalidStructure) }
  finish_state(w)
  (
    w.max_bytes - w.remaining_bytes,
    w.max_nodes - w.remaining_nodes,
    w.peak_depth,
  )
}

///|
fn finish_state(w : Writer) -> Unit raise EncodeFailure {
  active(w)
  if !w.root_written || !w.frames.is_empty() {
    fail(w, InvalidStructure)
  }
  w.closed = true
}

///|
/// A digest is exposed only after successful completion; wrong sink types close the writer.
pub fn finish_hash(w : Writer) -> String raise EncodeFailure {
  finish_hash_usage(w).0
}

///|
/// Complete the hash sink once, returning (hex digest, UTF-8 bytes, value nodes).
/// Counts cover the same successfully emitted stream, not a second traversal.
pub fn finish_hash_usage(w : Writer) -> (String, Int, Int) raise EncodeFailure {
  active(w)
  guard w.output is HashOutput(h) else { fail(w, InvalidStructure) }
  finish_state(w)
  let hex = @sha256.finish_hex(h) catch {
    @sha256.ClosedHasher => fail(w, ClosedWriter)
    @sha256.MessageTooLong => fail(w, OutputLimit)
  }
  (hex, w.max_bytes - w.remaining_bytes, w.max_nodes - w.remaining_nodes)
}
