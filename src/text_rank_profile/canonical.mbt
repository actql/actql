///|
priv enum Frame {
  Value(@decode.Cursor)
  Key(String)
  EndArray
  EndObject
}

///|
fn canonical_hash(c : @decode.Cursor, limits : Limits) -> String raise Stop {
  try {
    let w = @encode.hashing_writer(
      limits.max_profile_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    let stack : Array[Frame] = [Value(c)]
    while stack.pop() is Some(frame) {
      match frame {
        Key(name) => @encode.key(w, name)
        EndArray => @encode.end_array(w)
        EndObject => @encode.end_object(w)
        Value(at) =>
          match @decode.view(at) {
            NullValue => @encode.null_value(w)
            BoolValue(v) => @encode.bool_value(w, v)
            NumberValue(v) => @encode.number_value(w, v)
            TextValue(v) => @encode.string_value(w, v)
            ArrayValue(xs) => {
              @encode.begin_array(w)
              stack.push(EndArray)
              for i = xs.length() - 1; i >= 0; i = i - 1 {
                stack.push(Value(xs[i]))
              }
            }
            ObjectValue(o) => {
              let names = decoded(@decode.object_field_names(at))
              names.sort_by(@canonical.compare_utf16)
              @encode.begin_object(w)
              stack.push(EndObject)
              for i = names.length() - 1; i >= 0; i = i - 1 {
                stack.push(Value(required(o, names[i])))
                stack.push(Key(names[i]))
              }
            }
          }
      }
    }
    "sha256:" + @encode.finish_hash(w)
  } catch {
    Stop(e) => raise Stop(e)
    _ => raise Stop(BudgetExceeded)
  }
}
