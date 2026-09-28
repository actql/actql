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
  BufferedHashOutput(BufferedHash)
}

///|
// One bounded provisional batch, never a relation-sized text accumulator.
// Draining transfers bytes, not permission to publish a completed document.
priv struct BufferedHash {
  hash : @sha256.Hasher
  text : StringBuilder
  limit : Int
  mut bytes : Int
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
/// Emit and hash the same canonical stream in one traversal. The caller drains
/// provisional text between bounded batches and owns storage/I/O/backpressure.
/// No callback, file handle or platform-specific dependency enters this writer.
/// A batch overflow closes the writer, just like an aggregate output overflow.
pub fn buffered_hashing_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_buffer_bytes : Int,
) -> Writer raise EncodeFailure {
  if max_buffer_bytes < 0 {
    raise OutputLimit
  }
  create_writer(
    max_bytes,
    max_nodes,
    max_depth,
    BufferedHashOutput({
      hash: @sha256.hasher(),
      text: StringBuilder(),
      limit: max_buffer_bytes,
      bytes: 0,
    }),
  )
}

///|
/// Provisional canonical UTF-8 text only. Concatenate in drain order; draining
/// neither finalizes the document nor resets aggregate byte/node/depth limits.
/// All pending text must be drained before finish_hash[_usage].
pub fn drain_hash_output(w : Writer) -> String raise EncodeFailure {
  active(w)
  guard w.output is BufferedHashOutput(buffer) else {
    fail(w, InvalidStructure)
  }
  let text = buffer.text.to_string()
  buffer.text.reset()
  buffer.bytes = 0
  text
}

///|
fn reserve_buffer(w : Writer, bytes : Int) -> Unit raise EncodeFailure {
  if w.output is BufferedHashOutput(buffer) {
    if bytes > buffer.limit - buffer.bytes {
      fail(w, OutputLimit)
    }
    buffer.bytes += bytes
  }
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
    @sha256.InvalidAsciiRange => fail(w, InvalidUnicode)
  }
}

///|
fn hash_ascii_range(
  w : Writer,
  h : @sha256.Hasher,
  text : String,
  start : Int,
  end : Int,
) -> Unit raise EncodeFailure {
  @sha256.update_ascii_range(h, text, start, end) catch {
    @sha256.ClosedHasher => fail(w, ClosedWriter)
    @sha256.MessageTooLong => fail(w, OutputLimit)
    @sha256.InvalidAsciiRange => fail(w, InvalidUnicode)
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
  reserve_buffer(w, text.length())
  w.remaining_bytes -= text.length()
  match w.output {
    TextOutput(output) => output.write_string(text)
    MeasureOutput => ()
    HashOutput(h) => hash_ascii_range(w, h, text, 0, text.length())
    BufferedHashOutput(buffer) => {
      hash_ascii_range(w, buffer.hash, text, 0, text.length())
      buffer.text.write_string(text)
    }
  }
}

///|
fn quoted(w : Writer, text : String) -> Unit raise EncodeFailure {
  ascii(w, "\"")
  let mut i = 0
  while i < text.length() {
    let unit = text[i].to_int()
    if unit >= 32 && unit < 128 && unit != 34 && unit != 92 {
      // Bounded ASCII spans avoid a builder append and buffer reservation for
      // every ordinary character. Inspect at most one byte beyond the current
      // allowance, preserving limit failure before a later invalid surrogate.
      let capacity = match w.output {
        BufferedHashOutput(buffer) =>
          Int::min(w.remaining_bytes, buffer.limit - buffer.bytes)
        _ => w.remaining_bytes
      }
      let bound = Int::min(256, capacity)
      let start = i
      while i < text.length() && i - start <= bound {
        let next = text[i].to_int()
        if next < 32 || next >= 128 || next == 34 || next == 92 {
          break
        }
        i += 1
      }
      ascii_span(w, text, start, i)
      continue
    }
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
        reserve_buffer(w, bytes)
        w.remaining_bytes -= bytes
        match w.output {
          TextOutput(output) => output.write_char(scalar.unsafe_to_char())
          MeasureOutput => ()
          HashOutput(h) => hash_scalar(w, h, scalar)
          BufferedHashOutput(buffer) => {
            hash_scalar(w, buffer.hash, scalar)
            buffer.text.write_char(scalar.unsafe_to_char())
          }
        }
      }
    }
    i += 1
  }
  ascii(w, "\"")
}

///|
// Only quoted() calls this with a checked printable-ASCII slice, at most 257
// bytes. Measurement/hashing allocate no substring; text sinks append once.
fn ascii_span(
  w : Writer,
  text : String,
  start : Int,
  end : Int,
) -> Unit raise EncodeFailure {
  let size = end - start
  if size > w.remaining_bytes {
    fail(w, OutputLimit)
  }
  reserve_buffer(w, size)
  w.remaining_bytes -= size
  match w.output {
    MeasureOutput => ()
    TextOutput(output) =>
      output.write_string(text.unsafe_substring(start~, end~))
    HashOutput(hash) => hash_ascii_range(w, hash, text, start, end)
    BufferedHashOutput(buffer) => {
      hash_ascii_range(w, buffer.hash, text, start, end)
      buffer.text.write_string(text.unsafe_substring(start~, end~))
    }
  }
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
/// Write exact decimal text as a JSON number, never through binary64. The
/// text is `-?(0|[1-9][0-9]*)(\.[0-9]+)?`: no exponent, no leading `+`, no
/// redundant leading zero, and no negative zero.
pub fn decimal_number_value(
  w : Writer,
  text : String,
) -> Unit raise EncodeFailure {
  active(w)
  let size = text.length()
  let start = if size > 0 && text[0] == '-' { 1 } else { 0 }
  let mut index = start
  let mut nonzero = false
  while index < size && text[index] >= '0' && text[index] <= '9' {
    nonzero = nonzero || text[index] != '0'
    index += 1
  }
  let integer_digits = index - start
  if integer_digits == 0 || (integer_digits > 1 && text[start] == '0') {
    fail(w, InvalidNumber)
  }
  if index < size {
    if text[index] != '.' || index + 1 == size {
      fail(w, InvalidNumber)
    }
    index += 1
    while index < size {
      if text[index] < '0' || text[index] > '9' {
        fail(w, InvalidNumber)
      }
      nonzero = nonzero || text[index] != '0'
      index += 1
    }
  }
  if start == 1 && !nonzero {
    fail(w, InvalidNumber)
  }
  value_start(w)
  ascii(w, text)
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
  finish_text_usage(w).0
}

///|
/// Close one text writer and return the retained text with exact UTF-8 byte,
/// value-node, and peak-depth usage from that same traversal.
pub fn finish_text_usage(
  w : Writer,
) -> (String, Int, Int, Int) raise EncodeFailure {
  active(w)
  guard w.output is TextOutput(output) else { fail(w, InvalidStructure) }
  finish_state(w)
  (
    output.to_string(),
    w.max_bytes - w.remaining_bytes,
    w.max_nodes - w.remaining_nodes,
    w.peak_depth,
  )
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
/// Current successful output usage without closing the writer. A caller may
/// compare snapshots around one complete value; an open container's prefix is
/// included in both snapshots. No digest or provisional text is exposed.
pub fn writer_progress(w : Writer) -> (Int, Int, Int) raise EncodeFailure {
  active(w)
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
  let (hash, bytes, nodes, _) = finish_hash_metrics(w)
  (hash, bytes, nodes)
}

///|
/// Complete once and expose the actual peak container depth as well as usage.
/// A retained identity may use these metrics to enforce subsequent hash limits
/// without rescanning the immutable value or assuming the original ceiling.
pub fn finish_hash_metrics(
  w : Writer,
) -> (String, Int, Int, Int) raise EncodeFailure {
  active(w)
  let h = match w.output {
    HashOutput(h) => h
    BufferedHashOutput(buffer) => {
      if buffer.bytes != 0 {
        fail(w, InvalidStructure)
      }
      buffer.hash
    }
    TextOutput(_) | MeasureOutput => fail(w, InvalidStructure)
  }
  finish_state(w)
  let hex = @sha256.finish_hex(h) catch {
    @sha256.ClosedHasher => fail(w, ClosedWriter)
    @sha256.MessageTooLong => fail(w, OutputLimit)
    @sha256.InvalidAsciiRange => fail(w, InvalidUnicode)
  }
  (
    hex,
    w.max_bytes - w.remaining_bytes,
    w.max_nodes - w.remaining_nodes,
    w.peak_depth,
  )
}
