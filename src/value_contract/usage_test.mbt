///|
test "checked usage preserves admission behavior and reports exact shared-budget charges" {
  let root = cursor("{\"type\":\"number\",\"nullable\":false}")
  let (contract, nodes, text) = @value_contract.read_checked_usage(
    root,
    limits(),
  ).unwrap()
  assert_eq(nodes, 1)
  assert_eq(text, 6)
  assert_true(
    @value_contract.type_equal(
      contract,
      @value_contract.read_checked(root, limits()).unwrap(),
      100,
    ),
  )
  assert_true(
    @value_contract.read_checked_usage(root, limits(nodes~, text~, depth=0))
    is Ok(_),
  )
  assert_true(
    @value_contract.read_checked_usage(root, limits(nodes=0)) is Err(_),
  )
  assert_true(
    @value_contract.read_checked_usage(root, limits(text=5)) is Err(_),
  )
  let bad = cursor("{\"type\":\"object\",\"nullable\":false,\"fields\":{}}")
  assert_true(
    @value_contract.read_checked(bad, limits()) is Err(e) &&
    @value_contract.read_checked_usage(bad, limits()) is Err(other) &&
    e == other,
  )
  assert_true(
    @value_contract.read_checked_usage(root, limits(nodes=-1))
    is Err(InvalidLimits),
  )
}
