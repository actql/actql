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
/// Emit an admitted value's canonical typed JSON wire representation into the
/// caller's bounded sink. This is not the tagged typed-identity projection.
/// Objects retain admitted UTF-16 order; business keys are never interpreted.
/// The writer owns aggregate bytes/nodes/depth and finalization. Failed output
/// remains unavailable, including when embedding multiple values in one row.
pub fn emit_wire_value(
  value : Value,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[WireFrame] = [Read(value)]
  while pending.pop() is Some(frame) {
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
  }
}
