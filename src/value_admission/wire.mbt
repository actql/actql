///|
priv enum WireFrame {
  Read(Value)
  ArrayNext(FrozenArray[Value], Int)
  ObjectNext(FrozenArray[(String, Value)], Int)
  VectorNext(FrozenArray[Double], Int)
}

///|
// Admitted coefficients contain at most 38 digits. This bounded leaf conversion
// never parses through binary64 or a machine integer.
fn decimal_wire_text(value : DecimalValue) -> String {
  if value.scale == 0 {
    return value.coefficient
  }
  let negative = value.coefficient.has_prefix("-")
  let digits = if negative {
    value.coefficient[1:].to_owned()
  } else {
    value.coefficient
  }
  let padded = String::make((value.scale + 1 - digits.length()).max(0), '0') +
    digits
  let split = padded.length() - value.scale
  (if negative { "-" } else { "" }) +
  padded[:split].to_owned() +
  "." +
  padded[split:].to_owned()
}

///|
/// Canonical scalar spelling used by the normative `to_string` conversion.
/// Structured values, references, and null have no scalar string conversion.
/// The caller supplies the complete output byte ceiling before any result is
/// exposed.
pub fn canonical_scalar_text(
  value : CheckedValue,
  max_utf8_bytes : Int,
) -> String? {
  if max_utf8_bytes < 0 {
    return None
  }
  let text = match value.value {
    Boolean(v) => if v { "true" } else { "false" }
    Number(v) => v.to_string()
    Text(v) | Date(v) | Timestamp(v) => v
    Decimal(v) => decimal_wire_text(v)
    Null | Array(_) | Object(_) | Vector(_) | Reference(_) => return None
  }
  match @scalar.admit_utf8_length(text, max_utf8_bytes) {
    Ok(_) => Some(text)
    Err(_) => None
  }
}

///|
/// Emit an admitted value's canonical typed JSON wire representation into the
/// caller's bounded sink. This is not the tagged typed-identity projection.
/// Objects retain admitted UTF-16 order; business keys are never interpreted.
/// The writer owns aggregate bytes/nodes/depth and finalization. Failed output
/// remains unavailable, including when embedding multiple values in one row.
pub fn emit_wire_value(
  value : Value,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let cursor = start_wire_emit(value, output)
  while !advance_wire_emit(cursor) {
    ()
  }
}

///|
/// Emit the retained canonical value without exposing the checked value's
/// mutable construction representation to another package.
pub fn emit_checked_wire_value(
  value : CheckedValue,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_wire_value(value.value, output)
}

///|
/// Resumable form of `emit_wire_value`: one node, key or container end per
/// advance into the same writer, so a caller can stop between nodes.
struct WireEmitCursor {
  pending : Array[WireFrame]
  output : @encode.Writer
}

///|
pub fn start_wire_emit(value : Value, output : @encode.Writer) -> WireEmitCursor {
  { pending: [Read(value)], output }
}

///|
/// Drop pending frames; the writer stays owned by the caller.
pub fn cancel_wire_emit(cursor : WireEmitCursor) -> Unit {
  cursor.pending.clear()
}

///|
/// Emit one frame. Returns true once the value is completely written.
pub fn advance_wire_emit(
  cursor : WireEmitCursor,
) -> Bool raise @encode.EncodeFailure {
  let pending = cursor.pending
  let output = cursor.output
  guard pending.pop() is Some(frame) else { return true }
  match frame {
    Read(value) =>
      match value {
        Null => @encode.null_value(output)
        Boolean(v) => @encode.bool_value(output, v)
        Number(v) => @encode.number_value(output, v)
        Text(v) | Date(v) | Timestamp(v) => @encode.string_value(output, v)
        Decimal(v) => @encode.string_value(output, decimal_wire_text(v))
        Array(items) => {
          @encode.begin_array(output)
          pending.push(ArrayNext(items, 0))
        }
        Object(items) => {
          @encode.begin_object(output)
          pending.push(ObjectNext(items, 0))
        }
        Vector(items) => {
          @encode.begin_array(output)
          pending.push(VectorNext(items, 0))
        }
        Reference(reference) => emit_reference(reference, output)
      }
    ArrayNext(items, index) =>
      if items.values.get(index) is Some(child) {
        pending.push(ArrayNext(items, index + 1))
        pending.push(Read(child))
      } else {
        @encode.end_array(output)
      }
    ObjectNext(items, index) =>
      if items.values.get(index) is Some((name, child)) {
        @encode.key(output, name)
        pending.push(ObjectNext(items, index + 1))
        pending.push(Read(child))
      } else {
        @encode.end_object(output)
      }
    VectorNext(items, index) =>
      if items.values.get(index) is Some(child) {
        @encode.number_value(output, child)
        pending.push(VectorNext(items, index + 1))
      } else {
        @encode.end_array(output)
      }
  }
  pending.is_empty()
}
