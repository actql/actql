///|
priv enum EmitWork {
  Emit(@wire.Cursor)
  ArrayNext(@wire.Cursor, Int)
  ObjectNext(@wire.Cursor, Int)
}

///|
// Traverse the complete admitted Program source with the bounded Writer.
// Metadata, authored field order and arrays are retained without optimization.
fn emit_body(
  root : @wire.Cursor,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let work = [Emit(root)]
  while work.pop() is Some(task) {
    match task {
      Emit(cursor) =>
        match @wire.view(cursor) {
          NullValue => @encode.null_value(out)
          BoolValue(b) => @encode.bool_value(out, b)
          NumberValue(n) => @encode.number_value(out, n)
          TextValue(s) => @encode.string_value(out, s)
          ArrayValue(_) => {
            @encode.begin_array(out)
            work.push(ArrayNext(cursor, 0))
          }
          ObjectValue(_) => {
            @encode.begin_object(out)
            work.push(ObjectNext(cursor, 0))
          }
        }
      ArrayNext(cursor, i) =>
        match @wire.element_at(cursor, i) {
          Some(child) => {
            work.push(ArrayNext(cursor, i + 1))
            work.push(Emit(child))
          }
          None => @encode.end_array(out)
        }
      ObjectNext(cursor, i) =>
        match @wire.field_at(cursor, i) {
          Some((key, child)) => {
            @encode.key(out, key)
            work.push(ObjectNext(cursor, i + 1))
            work.push(Emit(child))
          }
          None => @encode.end_object(out)
        }
    }
  }
}

///|
/// Serialize the complete admitted Program source, including annotations.
/// This is machine interchange, not an identity projection or text formatter.
pub fn emit_program_source(
  program : Program,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_body(program_body(program), out)
}
