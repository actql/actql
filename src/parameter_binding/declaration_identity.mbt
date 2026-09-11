///|
priv enum DeclarationFrame {
  Read(@decode.Cursor, Bool)
  ArrayRest(@decode.Cursor, Int, Int)
  ObjectRest(Array[(String, @decode.Cursor)], Int)
}

///|
/// Emit the admitted declaration without its top-level annotation. Defaults and
/// authored type constraints remain source values, not checked-type expansion.
pub fn emit_declaration(
  declaration : Declaration,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let pending : Array[DeclarationFrame] = [Read(declaration.source, true)]
  while pending.pop() is Some(frame) {
    match frame {
      Read(cursor, root) =>
        if @decode.array_length(cursor) is Some(count) {
          @encode.begin_array(output)
          pending.push(ArrayRest(cursor, 0, count))
        } else if @decode.object_length(cursor) is Some(count) {
          @encode.begin_object(output)
          let fields = []
          for i in 0..<count {
            let field = @decode.field_at(cursor, i).unwrap()
            if !root || field.0 != "meta" {
              fields.push(field)
            }
          }
          fields.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
          pending.push(ObjectRest(fields, 0))
        } else {
          match @decode.view(cursor) {
            @decode.NullValue => @encode.null_value(output)
            @decode.BoolValue(v) => @encode.bool_value(output, v)
            @decode.NumberValue(v) => @encode.number_value(output, v)
            @decode.TextValue(v) => @encode.string_value(output, v)
            _ => raise @encode.InvalidStructure
          }
        }
      ArrayRest(cursor, i, count) =>
        if i == count {
          @encode.end_array(output)
        } else {
          pending.push(ArrayRest(cursor, i + 1, count))
          pending.push(Read(@decode.element_at(cursor, i).unwrap(), false))
        }
      ObjectRest(fields, i) =>
        if i == fields.length() {
          @encode.end_object(output)
        } else {
          let (name, child) = fields[i]
          @encode.key(output, name)
          pending.push(ObjectRest(fields, i + 1))
          pending.push(Read(child, false))
        }
    }
  }
}
