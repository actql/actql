///|
test "same declaration preflight continues once into actual typed default and original result" {
  let root = cursor(
    "{\"x\":{\"type\":\"string\",\"default\":\"é\"},\"y\":{\"type\":\"number\"}}",
  )
  let (prepared, nodes, text) = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(nodes=6, text=31),
  )
  assert_eq((nodes, text), (6, 31))
  let prepared = prepared.unwrap()
  let first = @parameter_binding.finish_declaration_read(prepared).unwrap()
  let again = @parameter_binding.finish_declaration_read(prepared).unwrap()
  // A second original typed read would construct another Declarations owner.
  assert_true(physical_equal(first, again))
  assert_eq(@parameter_binding.declaration_usage(first), (6, 31))
  assert_eq(@parameter_binding.declaration_count(first), 2)
  let bound = @parameter_binding.bind(
    first,
    Some(cursor("{\"y\":1}")),
    values_limit(),
  ).unwrap()
  let values = ready(bound)
  assert_eq(values.length(), 2)
  assert_true(values[0].origin is @parameter_binding.Default)
  assert_true(values[0].value.value is @value.Text("é"))
  let (empty, n, b) = @parameter_binding.prepare_declaration_read(
    None,
    limits(nodes=0, text=0, parameters=0),
  )
  assert_eq((n, b), (0, 0))
  assert_eq(
    @parameter_binding.declaration_count(
      @parameter_binding.finish_declaration_read(empty.unwrap()).unwrap(),
    ),
    0,
  )
}

///|
test "declaration continuation preserves first typed refusal and one-short source usage" {
  let root = cursor("{\"x\":{\"type\":\"unknown\"}}")
  let (prepared, n, b) = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(nodes=3, text=12),
  )
  assert_eq((n, b), (3, 12))
  let original = prepared.unwrap()
  let first = @parameter_binding.finish_declaration_read(original)
  assert_true(
    first
    is Err(
      @parameter_binding.Contract(
        @contract.ContractIssue(@contract.UnknownType("unknown"), ..)
      )
    ),
  )
  let again = @parameter_binding.finish_declaration_read(original)
  assert_true(physical_equal(first, again))
  let (short, n, b) = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(nodes=2, text=12),
  )
  assert_true(
    short
    is Err(
      @parameter_binding.ParameterIssue(@parameter_binding.BudgetExceeded, ..)
    ),
  )
  assert_eq((n, b), (2, 1))
}

///|
test "ordinary declaration readers keep independent owners outside one split continuation" {
  let root = cursor("{\"x\":{\"type\":\"number\"}}")
  let first = @parameter_binding.read_declarations(
    Some(root),
    limits(nodes=3, text=11),
  ).unwrap()
  let second = @parameter_binding.read_declarations(
    Some(root),
    limits(nodes=3, text=11),
  ).unwrap()
  assert_false(physical_equal(first, second))
  assert_eq(@parameter_binding.declaration_usage(first), (3, 11))
  assert_eq(@parameter_binding.declaration_usage(second), (3, 11))
  let (failed, n, b) = @parameter_binding.observe_declarations(
    Some(root),
    limits(nodes=2, text=11),
  )
  assert_true(
    failed
    is Err(
      @parameter_binding.ParameterIssue(@parameter_binding.BudgetExceeded, ..)
    ),
  )
  assert_eq((n, b), (2, 1))
}
