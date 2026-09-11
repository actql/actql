///|
priv enum Frame {
  Visit(@decode.Cursor)
  ArrayNext(@decode.Cursor, Int, Int)
  ObjectNext(@decode.Cursor, Int, Int, String?, Bool)
}

///|
/// Canonical wire input is already key-ordered. Reject, never silently sort.
fn emit_cursor(
  root : @decode.Cursor,
  writer : @encode.Writer,
  omit_identity : Bool,
) -> Unit raise @encode.EncodeFailure {
  let pending = if omit_identity {
    @encode.begin_object(writer)
    [ObjectNext(root, 0, @decode.object_length(root).unwrap(), None, true)]
  } else {
    [Visit(root)]
  }
  while pending.pop() is Some(frame) {
    match frame {
      Visit(cursor) =>
        if @decode.object_length(cursor) is Some(count) {
          @encode.begin_object(writer)
          pending.push(ObjectNext(cursor, 0, count, None, false))
        } else if @decode.array_length(cursor) is Some(count) {
          @encode.begin_array(writer)
          pending.push(ArrayNext(cursor, 0, count))
        } else {
          match @decode.view(cursor) {
            NullValue => @encode.null_value(writer)
            BoolValue(v) => @encode.bool_value(writer, v)
            NumberValue(v) => @encode.number_value(writer, v)
            TextValue(v) => @encode.string_value(writer, v)
            _ => raise @encode.InvalidStructure
          }
        }
      ArrayNext(cursor, i, count) =>
        if i == count {
          @encode.end_array(writer)
        } else {
          pending.push(ArrayNext(cursor, i + 1, count))
          pending.push(Visit(@decode.element_at(cursor, i).unwrap()))
        }
      ObjectNext(cursor, i, count, previous, omit) =>
        if i == count {
          @encode.end_object(writer)
        } else {
          let (key, value) = @decode.field_at(cursor, i).unwrap()
          if previous is Some(p) && @unicode.compare_utf16(p, key) >= 0 {
            raise @encode.InvalidStructure
          }
          pending.push(ObjectNext(cursor, i + 1, count, Some(key), omit))
          if !(omit && key == "evidence_bundle_cid") {
            @encode.key(writer, key)
            pending.push(Visit(value))
          }
        }
    }
  }
}
