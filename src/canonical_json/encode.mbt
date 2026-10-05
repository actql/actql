///|
/// Typed projection only: values already own normalized text and sorted keys.
/// Writing into a caller-owned bounded writer also charges the enclosing output.
priv enum EmitFrame {
  Visit(CanonicalValue)
  ArrayRest(EmitArrayCursor)
  ObjectRest(EmitObjectCursor)
}

///|
/// Existing canonical emission, resumed one node, key or container end at a
/// time. The caller owns the bounded writer and aggregate output accounting.
struct CanonicalEmit {
  pending : Array[EmitFrame]
  output : @encode.Writer
}

///|
pub fn start_emit(
  value : CanonicalValue,
  output : @encode.Writer,
) -> CanonicalEmit {
  { pending: [Visit(value)], output, }
}

///|
pub fn cancel_emit(cursor : CanonicalEmit) -> Unit {
  cursor.pending.clear()
}

///|
pub fn advance_emit(cursor : CanonicalEmit) -> Bool raise @encode.EncodeFailure {
  let pending = cursor.pending
  let output = cursor.output
  // Keep a container's continuation in place between children. Rewrapping
  // it on every advance adds allocation without changing the node/key work.
  guard pending.last() is Some(frame) else { return true }
  match frame {
    Visit(current) => {
      ignore(pending.pop())
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
    }
    ArrayRest(rest) =>
      if rest.index < rest.values.values.length() {
        let child = rest.values.values[rest.index]
        rest.index += 1
        pending.push(Visit(child))
      } else {
        ignore(pending.pop())
        @encode.end_array(output)
      }
    ObjectRest(rest) =>
      if rest.index < rest.values.values.length() {
        let (key, child) = rest.values.values[rest.index]
        @encode.key(output, key)
        rest.index += 1
        pending.push(Visit(child))
      } else {
        ignore(pending.pop())
        @encode.end_object(output)
      }
  }
  pending.is_empty()
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
  let cursor = start_emit(value, output)
  while !advance_emit(cursor) {
    ()
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
