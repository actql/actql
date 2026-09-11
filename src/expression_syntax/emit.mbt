///|
priv enum SourceFrame {
  Value(@decode.Cursor)
  ArrayRest(@decode.Cursor, Int, Int)
  ObjectRest(Array[(String, @decode.Cursor)], Int)
}

///|
/// Emit the admitted normalized source tree, not lowered expression nodes.
/// Parameters remain references and literal payloads remain data. Source
/// locations are sidecars and are never emitted. The caller supplies the shared
/// bounded text, measurement or hash writer for the enclosing semantic body.
pub fn emit_source(
  expression : Expression,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[SourceFrame] = [Value(tree(expression))]
  while pending.pop() is Some(frame) {
    match frame {
      Value(cursor) =>
        if @decode.array_length(cursor) is Some(count) {
          @encode.begin_array(writer)
          pending.push(ArrayRest(cursor, 0, count))
        } else if @decode.object_length(cursor) is Some(count) {
          @encode.begin_object(writer)
          let fields = []
          for i in 0..<count {
            fields.push(@decode.field_at(cursor, i).unwrap())
          }
          fields.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
          pending.push(ObjectRest(fields, 0))
        } else {
          match @decode.view(cursor) {
            @decode.NullValue => @encode.null_value(writer)
            @decode.BoolValue(v) => @encode.bool_value(writer, v)
            @decode.NumberValue(v) => @encode.number_value(writer, v)
            @decode.TextValue(v) => @encode.string_value(writer, v)
            _ => raise @encode.InvalidStructure
          }
        }
      ArrayRest(cursor, i, count) =>
        if i == count {
          @encode.end_array(writer)
        } else {
          pending.push(ArrayRest(cursor, i + 1, count))
          pending.push(Value(@decode.element_at(cursor, i).unwrap()))
        }
      ObjectRest(fields, i) =>
        if i == fields.length() {
          @encode.end_object(writer)
        } else {
          let (name, child) = fields[i]
          @encode.key(writer, name)
          pending.push(ObjectRest(fields, i + 1))
          pending.push(Value(child))
        }
    }
  }
}
