///|
fn search_test_cursor(source : String) -> @decode.Cursor {
  let node = @source.parse_json(source, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 1000,
    max_depth: 20,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
}

///|
test "canonical parameter search preserves prefixes and exact work" {
  let declarations = @parameter.read_declarations(
    Some(
      search_test_cursor(
        "{\"count\":{\"type\":\"string\",\"default\":\"a\"},\"counter\":{\"type\":\"string\",\"default\":\"b\"},\"n\":{\"type\":\"string\",\"default\":\"c\"}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 20,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let values = match
    @parameter.bind(declarations, Some(search_test_cursor("{}")), {
      max_nodes: 1000,
      max_depth: 20,
      max_text_bytes: 10000,
    }).unwrap() {
    @parameter.Ready(value) => value
    _ => abort("expected ready bindings")
  }
  let count = @parameter.bound_value_count(values)
  let at = position => @parameter.bound_value_at(values, position)
  for name in ["count", "counter", "n"] {
    let (found, _) = search_bound_parameter(name, count, at, 100).unwrap()
    assert_eq(found.unwrap().name, name)
  }
  let (missing, _) = search_bound_parameter("counts", count, at, 100).unwrap()
  assert_true(missing is None)
  assert_true(search_bound_parameter("count", count, at, 23) is Err(_))
  let (found, remaining) = search_bound_parameter("count", count, at, 24).unwrap()
  assert_eq(found.unwrap().name, "count")
  assert_eq(remaining, 0)
}
