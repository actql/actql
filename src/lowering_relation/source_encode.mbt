///|
priv enum SourceFrame {
  Value(@decode.Cursor)
  ArrayRest(@decode.Cursor, Int, Int)
  ObjectRest(@decode.Cursor, Int, Int)
}

///|
/// Emit the normalized source retained by the exact checked root. Parameters
/// remain source references here, unlike the bound machine node. Literal data
/// is traversed only for encoding, never interpreted as expression vocabulary.
/// The caller's Writer owns cumulative output/node/depth limits and publication.
/// Object enumeration is preserved, as in encode_core.emit_json. This is a
/// source-value projection, not a canonical-byte serializer or a CID preimage.
/// The enclosing canonical artifact must use its canonical object ordering.
pub fn emit_root_source(
  root : ExpressionRoot,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let source = @syntax.tree(@typing.expression(root.typed_expression))
  let pending : Array[SourceFrame] = [Value(source)]
  while pending.pop() is Some(frame) {
    match frame {
      Value(cursor) =>
        // Inspect container sizes without the copying ArrayValue accessor.
        if @decode.array_length(cursor) is Some(count) {
          @encode.begin_array(out)
          pending.push(ArrayRest(cursor, 0, count))
        } else if @decode.object_length(cursor) is Some(count) {
          @encode.begin_object(out)
          pending.push(ObjectRest(cursor, 0, count))
        } else {
          match @decode.view(cursor) {
            NullValue => @encode.null_value(out)
            BoolValue(v) => @encode.bool_value(out, v)
            NumberValue(v) => @encode.number_value(out, v)
            TextValue(v) => @encode.string_value(out, v)
            ArrayValue(_) | ObjectValue(_) => raise @encode.InvalidStructure
          }
        }
      ArrayRest(cursor, i, count) =>
        if i == count {
          @encode.end_array(out)
        } else {
          guard @decode.element_at(cursor, i) is Some(child) else {
            raise @encode.InvalidStructure
          }
          pending.push(ArrayRest(cursor, i + 1, count))
          pending.push(Value(child))
        }
      ObjectRest(cursor, i, count) =>
        if i == count {
          @encode.end_object(out)
        } else {
          guard @decode.field_at(cursor, i) is Some((name, child)) else {
            raise @encode.InvalidStructure
          }
          @encode.key(out, name)
          pending.push(ObjectRest(cursor, i + 1, count))
          pending.push(Value(child))
        }
    }
  }
}
