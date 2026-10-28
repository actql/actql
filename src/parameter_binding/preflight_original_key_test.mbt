///|
test "indexed declaration preflight preserves first original key path span and source order" {
  // This boundary validates retained literal data. The older authored-Source
  // helper normalizes/sorts keys before this reader, so it is not this input.
  let source = @source.parse_json_literal(
      "{\"e\\u0301\":{\"type\":\"number\"},\"later\":{\"type\":\"unknown\"}}",
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
    ).unwrap().node
  let root = @decode.admit(source, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  let child = @decode.field_at(root, 0).unwrap().1
  let (outcome, nodes, bytes) = @parameter_binding.observe_declarations(
    Some(root),
    limits(nodes=100, text=1000),
  )
  guard outcome is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original preflight refusal")
  }
  assert_eq(kind, @parameter_binding.NonCanonicalText)
  assert_eq(path, @decode.cursor_path(child))
  assert_eq(span, @decode.cursor_key_span(child).unwrap())
  assert_eq((nodes, bytes), (3, 3))
  assert_eq(@decode.object_length(root), Some(2))
}

///|
test "indexed Parameter preflight keeps child and depth refusal ahead of scalar validation" {
  let root = cursor("{\"x\":{\"type\":\"string\",\"default\":\"é\"}}")
  let child = @decode.field_at(root, 0).unwrap().1
  let (short, nodes, bytes) = @parameter_binding.observe_declarations(
    Some(root),
    limits(nodes=3, text=1000),
  )
  guard short is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original node refusal")
  }
  assert_eq(kind, @parameter_binding.BudgetExceeded)
  assert_eq(path, @decode.cursor_path(child))
  assert_eq(span, @decode.cursor_span(child))
  assert_eq((nodes, bytes), (2, 1))
  let (depth, n, b) = @parameter_binding.observe_declarations(Some(root), {
    ..limits(nodes=100, text=1000),
    max_depth: 1,
  })
  guard depth is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original depth refusal")
  }
  assert_eq(kind, @parameter_binding.BudgetExceeded)
  assert_eq(path, @decode.cursor_path(child))
  assert_eq(span, @decode.cursor_span(child))
  assert_eq((n, b), (2, 1))
}
