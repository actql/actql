///|
test "deep arrays use explicit frames and bounded structural paths" {
  let depth = 10000
  let text = "[".repeat(depth) + "0" + "]".repeat(depth)
  let mut node = parse_json(text, limits(nodes=depth + 1, depth~)).unwrap()
  for _ in 0..<depth {
    guard node.value is Array(items) else { fail("expected nested array") }
    assert_eq(items.length(), 1)
    node = items[0]
  }
  assert_true(node.value is Number(0.0))
  guard parse_json(text, limits(depth=depth - 1)) is Err(error) else {
    fail("expected depth failure")
  }
  assert_eq(error.issue, DepthLimit)
  assert_eq(error.path.unwrap().length(), depth - 1)
  let malformed = "[".repeat(depth) + "?"
  guard parse_json(malformed, limits(depth~)) is Err(error) else {
    fail("expected token failure")
  }
  assert_eq(error.issue, UnexpectedToken)
  assert_eq(error.path.unwrap().length(), depth)
}

///|
test "wide objects preserve order and detect late duplicates using key admission" {
  let count = 10000
  let text = StringBuilder()
  text.write_string("{")
  for index in 0..<count {
    if index > 0 {
      text.write_string(",")
    }
    text.write_string("\"k" + index.to_string() + "\":0")
  }
  let prefix = text.to_string()
  guard parse_json(prefix + "}", limits(nodes=count + 1)).unwrap().value
    is Object(fields) else {
    fail("expected wide object")
  }
  assert_eq(fields.length(), count)
  for index in 0..<count {
    assert_eq(fields[index].key, "k" + index.to_string())
  }
  assert_eq(rejected(prefix + ",\"k9999\":?}").issue, DuplicateKey("k9999"))
}

///|
test "returned syntax arrays are editable without sharing across parses or siblings" {
  let text = "{\"a\":[1],\"b\":[2]}"
  let first = parsed(text)
  let second = parsed(text)
  guard first.value is Object(fields) else { fail("expected object") }
  guard fields[0].value.value is Array(a) else { fail("expected array") }
  guard fields[1].value.value is Array(b) else { fail("expected array") }
  a.clear()
  assert_eq(b.length(), 1)
  fields.clear()
  guard second.value is Object(other) else {
    fail("expected independent object")
  }
  assert_eq(other.length(), 2)
  guard other[0].value.value is Array(values) else {
    fail("expected independent array")
  }
  assert_eq(values.length(), 1)
}
