///|
priv enum JsonFrame {
  Value(Json)
  ArrayRest(Array[Json], Int)
  ObjectRest(Iter[(String, Json)])
}

///|
/// Borrowed in-memory JSON adapter, not a parser or semantic admission API.
/// Emits immediately, retains no aliases, and applies the caller's Writer
/// budgets to the whole traversal. Text and object iteration order are exact.
pub fn emit_json(value : Json, out : Writer) -> Unit raise EncodeFailure {
  // One continuation per open container; no recursive target call stack and
  // no width-sized copy of a caller's object/array before budget admission.
  let pending : Array[JsonFrame] = [Value(value)]
  while pending.pop() is Some(frame) {
    match frame {
      Value(value) =>
        match value {
          Null => null_value(out)
          True => bool_value(out, true)
          False => bool_value(out, false)
          Number(value, ..) => number_value(out, value)
          String(value) => string_value(out, value)
          Array(values) => {
            begin_array(out)
            pending.push(ArrayRest(values, 0))
          }
          Object(values) => {
            begin_object(out)
            pending.push(ObjectRest(values.iter()))
          }
        }
      ArrayRest(values, index) =>
        if index < values.length() {
          pending.push(ArrayRest(values, index + 1))
          pending.push(Value(values[index]))
        } else {
          end_array(out)
        }
      ObjectRest(entries) =>
        match entries.next() {
          Some((name, value)) => {
            key(out, name)
            pending.push(ObjectRest(entries))
            pending.push(Value(value))
          }
          None => end_object(out)
        }
    }
  }
}
