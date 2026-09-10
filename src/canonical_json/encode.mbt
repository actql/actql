///|
/// Typed projection only: values already own normalized text and sorted keys.
/// Writing into a caller-owned bounded writer also charges the enclosing output.
priv enum EmitFrame {
  ArrayRest(EmitArrayCursor)
  ObjectRest(EmitObjectCursor)
}

///|
priv struct EmitArrayCursor {
  values : FrozenArray[CanonicalValue]
  mut index : Int
}

///|
priv struct EmitObjectCursor {
  values : FrozenArray[(String, CanonicalValue)]
  mut index : Int
}

///|
pub fn emit_value(
  value : CanonicalValue,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[EmitFrame] = []
  let mut current = value
  let mut visiting = true
  while visiting || !pending.is_empty() {
    if visiting {
      visiting = false
      match current {
        Null => @encode.null_value(output)
        Bool(value) => @encode.bool_value(output, value)
        Number(value) => @encode.number_value(output, value)
        String(value) => @encode.string_value(output, value)
        Array(frozen) => {
          @encode.begin_array(output)
          pending.push(ArrayRest({ values: frozen, index: 0, }))
        }
        Object(frozen) => {
          @encode.begin_object(output)
          pending.push(ObjectRest({ values: frozen, index: 0, }))
        }
      }
    } else {
      let frame = pending[pending.length() - 1]
      match frame {
        ArrayRest(cursor) =>
          if cursor.index < cursor.values.values.length() {
            current = cursor.values.values[cursor.index]
            cursor.index += 1
            visiting = true
          } else {
            ignore(pending.pop())
            @encode.end_array(output)
          }
        ObjectRest(cursor) =>
          if cursor.index < cursor.values.values.length() {
            let (key, value) = cursor.values.values[cursor.index]
            @encode.key(output, key)
            current = value
            cursor.index += 1
            visiting = true
          } else {
            ignore(pending.pop())
            @encode.end_object(output)
          }
      }
    }
  }
}

///|
pub fn stringify_value(
  value : CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let output = @encode.writer(max_bytes, max_nodes, max_depth)
  emit_value(value, output)
  @encode.finish(output)
}

///|
/// Exact emitted UTF-8 size with the same encoder and admission limits.
/// The output sink retains no rendered text.
pub fn measure_value(
  value : CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int raise @encode.EncodeFailure {
  let output = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
  emit_value(value, output)
  @encode.finish_measurement(output)
}

///|
/// Hash exactly the canonical UTF-8 serialization, with no envelope rewriting.
pub fn cid_value(
  value : CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let output = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_value(value, output)
  "sha256:" + @encode.finish_hash(output)
}
