///|
test "contract registry budgets accumulate and do not reset per envelope" {
  let first = envelope("null", null_contract_cid())
  let second = envelope(
    "null", "sha256:0cd9ea53bd35ffe3bca321f4d2b4e725bddf9f885f9333570f197727e1cbd048",
  ).replace(old="example", new="other")
  let environment = registry_wire([first, second])
  let registry = check_contract_registry(environment, caps()).unwrap()
  let (bytes, nodes, members) = contract_registry_usage(registry)
  assert_eq(members, 2)
  assert_eq(bytes, first.length() + second.length())
  let exact = {
    ..caps(),
    max_bytes: bytes,
    max_nodes: nodes,
    max_members: members,
  }
  assert_true(check_contract_registry(environment, exact) is Ok(_))
  assert_true(
    check_contract_registry(environment, { ..exact, max_bytes: bytes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_contract_registry(environment, { ..exact, max_nodes: nodes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_contract_registry(environment, { ..exact, max_members: 1, })
    is Err(BudgetExceeded),
  )
  let other = registry_wire([first, second])
  assert_false(physical_equal(contract_registry_environment(registry), other))
}

///|
test "deep contract body is hashed without recursive traversal" {
  let body = "[".repeat(1000) + "null" + "]".repeat(1000)
  let preimage = "{\"body\":" +
    body +
    ",\"id\":\"example\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"external-7\"}"
  let identity = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let environment = registry_wire([envelope(body, identity)])
  assert_true(check_contract_registry(environment, caps()) is Ok(_))
  assert_true(
    check_contract_registry(environment, { ..caps(), max_depth: 1000, })
    is Err(BudgetExceeded),
  )
}
