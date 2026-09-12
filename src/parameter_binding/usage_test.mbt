///|
test "declaration and selected binding usage compose without resetting input budgets" {
  let root = cursor(
    "{\"x\":{\"type\":\"string\",\"default\":\"é\"},\"y\":{\"type\":\"number\"}}",
  )
  // Six source nodes. UTF-8 text: x/y (2), type twice (8), default (7),
  // string/number (12), and é (2). No JSON punctuation is charged.
  let declarations = @parameter_binding.read_declarations(
    Some(root),
    limits(nodes=6, text=31),
  ).unwrap()
  assert_eq(@parameter_binding.declaration_usage(declarations), (6, 31))
  let roomy = @parameter_binding.read_declarations(Some(root), limits()).unwrap()
  assert_eq(@parameter_binding.declaration_usage(roomy), (6, 31))
  for caps in [limits(nodes=5, text=31), limits(nodes=6, text=30)] {
    assert_true(
      @parameter_binding.read_declarations(Some(root), caps) is Err(_),
    )
  }
  let (nodes, text) = @parameter_binding.declaration_usage(declarations)
  // One aggregate allowance covers declaration preflight and selected values.
  let result = @parameter_binding.bind(
    declarations,
    Some(cursor("{\"y\":7}")),
    values_limit(nodes=8 - nodes, text=35 - text),
  ).unwrap()
  assert_true(result is @parameter_binding.Ready(_))
  assert_eq(@parameter_binding.binding_usage(result), (2, 4))
  for caps in [values_limit(nodes=1, text=4), values_limit(nodes=2, text=3)] {
    assert_true(
      @parameter_binding.bind(declarations, Some(cursor("{\"y\":7}")), caps)
      is Err(_),
    )
  }
  let supplied_default = @parameter_binding.bind(
    declarations,
    Some(cursor("{\"x\":\"é\",\"y\":7}")),
    values_limit(),
  ).unwrap()
  assert_eq(@parameter_binding.binding_usage(supplied_default), (2, 4))
  guard result is @parameter_binding.Ready(a) else { fail("expected ready") }
  guard supplied_default is @parameter_binding.Ready(b) else {
    fail("expected ready")
  }
  assert_eq(
    @parameter_binding.parameter_values_cid(a, 10000, 1000, 100),
    @parameter_binding.parameter_values_cid(b, 10000, 1000, 100),
  )
  assert_true(
    physical_equal(@parameter_binding.bound_declarations(a), declarations),
  )
}

///|
test "missing bindings retain selected usage without a partial ready set" {
  let declarations = declarations(
    "{\"x\":{\"type\":\"string\",\"default\":\"é\"},\"y\":{\"type\":\"number\"}}",
  )
  let result = @parameter_binding.bind(
    declarations,
    None,
    values_limit(nodes=1, text=3),
  ).unwrap()
  assert_eq(@parameter_binding.binding_usage(result), (1, 3))
  guard result is @parameter_binding.NeedsBindings(missing) else {
    fail("expected missing y")
  }
  let names = @parameter_binding.missing_names(missing)
  assert_eq(names, ["y"])
  names.clear()
  assert_eq(@parameter_binding.binding_usage(result), (1, 3))
  // Invalid supplied values still win over missing names; usage does not
  // provide an alternate success path or swallow a later error.
  assert_true(
    @parameter_binding.bind(
      declarations,
      Some(cursor("{\"y\":null}")),
      values_limit(),
    )
    is Err(_),
  )
  let none = @parameter_binding.read_declarations(
    None,
    limits(nodes=0, text=0, parameters=0),
  ).unwrap()
  assert_eq(@parameter_binding.declaration_usage(none), (0, 0))
  let empty = @parameter_binding.bind(
    none,
    Some(cursor("{}")),
    values_limit(nodes=0, text=0),
  ).unwrap()
  assert_true(empty is @parameter_binding.Ready(_))
  assert_eq(@parameter_binding.binding_usage(empty), (0, 0))
}

///|
test "binding usage counts nested values and scalar UTF-8 widths" {
  let declarations = declarations(
    "{\"a\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"default\":[\"é\",\"😀\"]},\"b\":{\"type\":\"number\",\"nullable\":true,\"default\":null}}",
  )
  let result = @parameter_binding.bind(
    declarations,
    None,
    values_limit(nodes=4, depth=1, text=8),
  ).unwrap()
  // Array + its two strings + null. Names a/b cost 2 bytes, strings cost 6.
  assert_eq(@parameter_binding.binding_usage(result), (4, 8))
  for
    caps in [
      values_limit(nodes=3, depth=1, text=8),
      values_limit(nodes=4, depth=1, text=7),
      values_limit(nodes=4, depth=0, text=8),
    ] {
    assert_true(@parameter_binding.bind(declarations, None, caps) is Err(_))
  }
}
