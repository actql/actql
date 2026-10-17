///|
test "bound cursor projection preserves the original value and rejects copied occurrence text" {
  let document =
    #|{"params":{"n":{"type":"number"}},"body":{"a/~":{"$param":"n"},"not_selected":{"$param":"n"}}}
  let root = cursor(document)
  let body = field(root, "body")
  let original = field(body, "a/~")
  let declarations = declarations_for(root)
  let index = build(body, declarations, [occurrences(original)], limits()).unwrap()
  let bound = bind_values(index, ready(declarations, "{\"n\":9}"), max_work=100).unwrap()
  let (selected, used) = bound_value_for_cursor(bound, original, 1000).unwrap()
  assert_true(
    physical_equal(selected.unwrap(), used_value_at(bound, 0).unwrap()),
  )
  assert_true(used > 0)
  assert_true(bound_value_for_cursor(bound, original, used) is Ok((Some(_), _)))
  assert_true(
    bound_value_for_cursor(bound, original, used - 1) is Err(WorkLimit),
  )
  assert_true(bound_value_for_cursor(bound, original, -1) is Err(InvalidLimits))
  assert_true(
    bound_value_for_cursor(bound, field(body, "not_selected"), 1000)
    is Ok((None, _)),
  )
  let copied = field(field(cursor(document), "body"), "a/~")
  assert_true(bound_value_for_cursor(bound, copied, 1000) is Ok((None, _)))
  assert_true(bound_value_for_cursor(bound, root, 1000) is Ok((None, _)))
}
