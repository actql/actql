///|
test "admission retains exact sizes independently of the original mutable tree" {
  let items = [node(@source.String("😀")), node(@source.Null)]
  let fields = [entry("é", node(@source.Array(items)))]
  let raw = node(@source.Object(fields))
  let cursor = admit(raw, budget()).unwrap()
  let expected : AdmissionUsage = {
    nodes: 4,
    depth: 2,
    largest_string_bytes: 4,
    total_string_bytes: 6,
  }
  assert_eq(admission_usage(cursor), expected)
  let child = field_at(cursor, 0).unwrap().1
  assert_eq(admission_usage(child), expected)
  assert_eq(admission_usage(element_at(child, 1).unwrap()), expected)
  assert_eq(admission_usage(elements(child).unwrap()[0]), expected)
  assert_eq(
    admission_usage(lookup(open_object(cursor).unwrap(), "é").unwrap()),
    expected,
  )
  guard view(child) is ArrayValue(detached) else { abort("array") }
  assert_eq(admission_usage(detached[0]), expected)
  items.push(node(@source.String("changed")))
  fields.push(entry("longer-field-name", node(@source.Null)))
  assert_eq(admission_usage(cursor), expected)
  assert_eq(array_length(child), Some(2))
  assert_true(admit(raw, budget(nodes=4)) is Err(_))
}

///|
test "admission measurements cover field names and scalar depth zero" {
  assert_eq(admission_usage(owned(@source.String(""))), {
    nodes: 1,
    depth: 0,
    largest_string_bytes: 0,
    total_string_bytes: 0,
  })
  let root = node(
    @source.Object([entry("long-name", node(@source.String("x")))]),
  )
  let caps = budget(nodes=2, depth=1, string_bytes=9, total_bytes=10)
  assert_eq(admission_usage(admit(root, caps).unwrap()), {
    nodes: 2,
    depth: 1,
    largest_string_bytes: 9,
    total_string_bytes: 10,
  })
  for
    small in [
      budget(nodes=1),
      budget(depth=0),
      budget(string_bytes=8),
      budget(total_bytes=9),
    ] {
    assert_eq(rejection(admit(root, small)).kind, BudgetExceeded)
  }
}
