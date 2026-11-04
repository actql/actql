///|
/// Typed projection only: values already own normalized text and sorted keys.
/// Writing into a caller-owned bounded writer also charges the enclosing output.
priv enum EmitFrame {
  EmitRetired
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
  for index, frame in cursor.pending {
    match frame {
      TextNext(text) => @encode.cancel_string_value(text)
      KeyNext(key) => @encode.cancel_ordered_key(key)
      _ => ()
    }
    cursor.pending[index] = EmitRetired
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
/// Actual retained native/JS array backing, not current pending occupancy.
/// Retired slots are payload-free; completed child owners are not hidden here.
pub fn emit_storage_frames(cursor : CanonicalEmit) -> Int {
  cursor.pending.capacity()
}

///|
pub fn advance_emit(cursor : CanonicalEmit) -> Bool raise @encode.EncodeFailure {
  let pending = cursor.pending
  let output = cursor.output
  guard pending.last() is Some(frame) else { return true }
  // Remove native stale payload ownership without scanning unused capacity.
  pending[pending.length() - 1] = EmitRetired
  pending.truncate(pending.length() - 1)
  match frame {
    EmitRetired => raise @encode.InvalidStructure
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
priv enum SyncEmitParent {
  Elements(EmitArrayCursor)
  Fields(EmitObjectCursor)
}

///|
pub fn emit_value(
  value : CanonicalValue,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  // This caller completes synchronously: retain only open containers, not a
  // resumable Visit/Rest pair for every child. Writer operations and their
  // failure order stay identical to the incremental emitter above.
  let parents : Array[SyncEmitParent] = []
  let mut current = value
  let mut visit = true
  while true {
    if visit {
      match current {
        Null => @encode.null_value(output)
        Bool(value) => @encode.bool_value(output, value)
        Number(value) => @encode.number_value(output, value)
        String(value) =>
          if value.length() <= 64 {
            @encode.string_value(output, value)
          } else {
            let text = @encode.start_string_value(output, value)
            while !@encode.advance_string_value(text) {
              ()
            }
          }
        Array(values) => {
          @encode.begin_array(output)
          parents.push(Elements({ values, index: 0, }))
        }
        Object(values) => {
          @encode.begin_ordered_object(output)
          parents.push(Fields({ values, index: 0, }))
        }
      }
      visit = false
    }
    if parents.is_empty() {
      break
    }
    match parents[parents.length() - 1] {
      Elements(rest) =>
        if rest.index < rest.values.values.length() {
          current = rest.values.values[rest.index]
          rest.index += 1
          visit = true
        } else {
          @encode.end_array(output)
          ignore(parents.pop())
        }
      Fields(rest) =>
        if rest.index < rest.values.values.length() {
          let (key, child) = rest.values.values[rest.index]
          @encode.ordered_key(output, key)
          rest.index += 1
          current = child
          visit = true
        } else {
          @encode.end_object(output)
          ignore(parents.pop())
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
  stringify_value_with_usage(value, max_bytes, max_nodes, max_depth).0
}

///|
/// Retain exact usage from the SAME original text writer. The ordinary text
/// projection and its immutable-bound facts share one emission algorithm.
pub fn stringify_value_with_usage(
  value : CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (String, Int, Int, Int) raise @encode.EncodeFailure {
  let output = @encode.writer(max_bytes, max_nodes, max_depth)
  emit_value(value, output)
  @encode.finish_text_usage(output)
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
