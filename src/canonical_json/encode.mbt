///|
/// Typed projection only: values already own normalized text and sorted keys.
/// Writing into a caller-owned bounded writer also charges the enclosing output.
priv enum EmitFrame {
  Visit(CanonicalValue)
  TextNext(@encode.StringEmitCursor)
  KeyNext(@encode.OrderedKeyEmitCursor)
  ArrayRest(EmitArrayCursor)
  ObjectRest(EmitObjectCursor)
  ObjectValueRest(EmitObjectCursor)
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
  for frame in cursor.pending {
    match frame {
      TextNext(text) => @encode.cancel_string_value(text)
      KeyNext(key) => @encode.cancel_ordered_key(key)
      _ => ()
    }
  }
  cursor.pending.clear()
}

///|
/// Include nested canonical continuations in the caller's traversal reservation.
/// One advance grows this count by at most one; no pending-stack scan is needed.
pub fn emit_pending_frames(cursor : CanonicalEmit) -> Int {
  cursor.pending.length()
}

///|
pub fn advance_emit(cursor : CanonicalEmit) -> Bool raise @encode.EncodeFailure {
  let pending = cursor.pending
  let output = cursor.output
  guard pending.pop() is Some(frame) else { return true }
  match frame {
    Visit(current) =>
      match current {
        Null => @encode.null_value(output)
        Bool(value) => @encode.bool_value(output, value)
        Number(value) => @encode.number_value(output, value)
        String(value) =>
          if value.length() <= 64 {
            @encode.string_value(output, value)
          } else {
            pending.push(TextNext(@encode.start_string_value(output, value)))
          }
        Array(frozen) => {
          @encode.begin_array(output)
          pending.push(ArrayRest({ values: frozen, index: 0, }))
        }
        Object(frozen) => {
          @encode.begin_ordered_object(output)
          pending.push(ObjectRest({ values: frozen, index: 0, }))
        }
      }
    ArrayRest(rest) =>
      if rest.index < rest.values.values.length() {
        let child = rest.values.values[rest.index]
        rest.index += 1
        pending.push(ArrayRest(rest))
        pending.push(Visit(child))
      } else {
        @encode.end_array(output)
      }
    ObjectRest(rest) =>
      if rest.index < rest.values.values.length() {
        let (key, child) = rest.values.values[rest.index]
        if key.length() > 64 {
          let cursor = @encode.start_ordered_key(output, key)
          pending.push(ObjectValueRest(rest))
          pending.push(KeyNext(cursor))
        } else {
          @encode.ordered_key(output, key)
          rest.index += 1
          pending.push(ObjectRest(rest))
          pending.push(Visit(child))
        }
      } else {
        @encode.end_object(output)
      }
    ObjectValueRest(rest) => {
      let child = rest.values.values[rest.index].1
      rest.index += 1
      pending.push(ObjectRest(rest))
      pending.push(Visit(child))
    }
    TextNext(text) =>
      if !@encode.advance_string_value(text) {
        pending.push(TextNext(text))
      }
    KeyNext(key) =>
      if !@encode.advance_ordered_key(key) {
        pending.push(KeyNext(key))
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
