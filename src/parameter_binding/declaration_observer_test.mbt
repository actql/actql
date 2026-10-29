///|
test "original declaration observer keeps success absent and invalid-limit usage without another reader" {
  let root = cursor(
    "{\"x\":{\"type\":\"string\",\"default\":\"é\"},\"y\":{\"type\":\"number\"}}",
  )
  let (result, nodes, text) = @parameter_binding.observe_declarations(
    Some(root),
    limits(nodes=6, text=31),
  )
  let declarations = result.unwrap()
  // Independent existing source positions/UTF8 rule:6nodes; names2,
  // type keys8, default key7, string/number12 and é2bytes =>31.
  assert_eq((nodes, text), (6, 31))
  assert_eq(@parameter_binding.declaration_usage(declarations), (6, 31))
  assert_eq(@parameter_binding.declaration_count(declarations), 2)
  let (empty, nodes, text) = @parameter_binding.observe_declarations(
    None,
    limits(nodes=0, text=0, parameters=0),
  )
  assert_eq(@parameter_binding.declaration_count(empty.unwrap()), 0)
  assert_eq((nodes, text), (0, 0))
  let (invalid, nodes, text) = @parameter_binding.observe_declarations(
    Some(root),
    limits(nodes=-1),
  )
  assert_true(invalid is Err(@parameter_binding.InvalidLimits))
  assert_eq((nodes, text), (0, 0))
}

///|
test "original declaration observer retains preflight before typed contract and source budget refusals" {
  let (result, nodes, text) = @parameter_binding.observe_declarations(
    Some(
      cursor(
        "{\"x\":{\"type\":\"unknown\",\"default\":\"é\"},\"y\":{\"type\":\"number\"}}",
      ),
    ),
    limits(),
  )
  assert_true(
    result
    is Err(
      @parameter_binding.Contract(
        @contract.ContractIssue(@contract.UnknownType("unknown"), ..)
      )
    ),
  )
  // Same6positions. unknown replaces string with one extra UTF8byte;
  // original full preflight completes before the original type refusal.
  assert_eq((nodes, text), (6, 32))
  let (short, nodes, text) = @parameter_binding.observe_declarations(
    Some(
      cursor(
        "{\"x\":{\"type\":\"string\",\"default\":\"é\"},\"y\":{\"type\":\"number\"}}",
      ),
    ),
    limits(nodes=5, text=31),
  )
  assert_true(
    short
    is Err(
      @parameter_binding.ParameterIssue(@parameter_binding.BudgetExceeded, ..)
    ),
  )
  // Root reserves x/y; x reserves type/default. Namesx/y2 +xkeys11
  // +string6 +é2=21. y's child reservation then refuses, not refunded.
  assert_eq((nodes, text), (5, 21))
}
