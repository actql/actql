///|
fn funded_parameter_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_literal(text, {
      max_input_bytes: 10000,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap().node,
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn funded_parameter_limits() -> @parameters.DeclarationLimits {
  { max_parameters: 2, max_nodes: 3, max_depth: 2, max_text_bytes: 11, }
}

///|
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
fn funded_value_limits() -> @parameters.DeclarationLimits {
  {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 10,
    max_text_bytes: 100000,
  }
}

///|
extern "js" fn source_current_stop() -> Unit =
  #|() => {throw new Error('SourceCurrentStopped');}
