///|
#cfg(target="js")
fn funded_value_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_literal(text, {
      max_input_bytes: 100000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap().node,
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
#cfg(target="js")
extern "js" fn source_current_stop() -> Unit =
  #|() => {throw new Error('SourceCurrentStopped');}
