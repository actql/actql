///|
fn source_publication_cursor(
  wire : String,
) -> @decode.Cursor raise ClientSourceStop {
  let node = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: 1048576,
    max_nodes: 16384,
    max_depth: 32,
  }).unwrap_or_else(() => raise ClientSourceStop(Publication))
  @decode.admit(node, {
    max_nodes: 16384,
    max_depth: 32,
    max_string_bytes: 65536,
    max_total_string_bytes: 1048576,
  }).unwrap_or_else(() => raise ClientSourceStop(Publication))
}

///|
fn source_publication_field(
  value : @decode.Cursor,
  name : String,
) -> @decode.Cursor raise ClientSourceStop {
  let object = @decode.open_object(value).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
  @decode.required(object, name).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
}

///|
fn source_publication_text(
  value : @decode.Cursor,
  name : String,
) -> String raise ClientSourceStop {
  @decode.text(source_publication_field(value, name)).unwrap_or_else(() => {
    raise ClientSourceStop(Publication)
  })
}
