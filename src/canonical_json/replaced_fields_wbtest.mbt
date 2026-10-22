///|
fn replacement_test_value(wire : String) -> CanonicalValue {
  let source = @source.parse_json(wire, {
    max_input_bytes: 1024,
    max_nodes: 32,
    max_depth: 8,
  }).unwrap()
  from_source(source, 32, 8, 1024) catch {
    _ => abort("Invalid replacement fixture")
  }
}

///|
test "existing canonical field replacement detaches the root and preserves children" {
  let original = replacement_test_value("{\"a\":null,\"b\":true,\"c\":null}")
  let child = replacement_test_value("{\"nested\":[\"雪\",7]}")
  let replacements = [("a", child), ("c", child)]
  let output = object_with_replaced_fields(original, replacements).unwrap()
  replacements.clear()
  assert_eq(
    stringify_value(original, 1024, 32, 8),
    "{\"a\":null,\"b\":true,\"c\":null}",
  )
  assert_eq(
    stringify_value(output, 1024, 32, 8),
    "{\"a\":{\"nested\":[\"雪\",7]},\"b\":true,\"c\":{\"nested\":[\"雪\",7]}}",
  )
  guard output is Object(fields) else { abort("Expected object") }
  let detached = array_values(fields)
  detached.clear()
  assert_eq(array_count(fields), 3)
}

///|
test "existing canonical field replacement refuses new repeated and reordered keys" {
  let original = replacement_test_value("{\"a\":null,\"b\":null}")
  let child = replacement_test_value("false")
  for
    replacements in [
      [("c", child)],
      [("a", child), ("a", child)],
      [("b", child), ("a", child)],
    ] {
    assert_true(object_with_replaced_fields(original, replacements) is None)
  }
  assert_true(object_with_replaced_fields(child, []) is None)
  assert_eq(
    stringify_value(
      object_with_replaced_fields(original, []).unwrap(),
      64,
      3,
      1,
    ),
    "{\"a\":null,\"b\":null}",
  )
}
