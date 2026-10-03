///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 1000,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 1000,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn limits() -> @graph_typing.Limits {
  {
    max_work: 10000,
    max_nodes: 10000,
    max_depth: 1000,
    max_text_bytes: 100000,
  }
}

///|
fn predicate_limits() -> @graph_typing.PredicateLimits {
  {
    max_work: 100000,
    max_nodes: 100000,
    max_depth: 1000,
    max_text_bytes: 100000,
    max_tokens: 100000,
  }
}
