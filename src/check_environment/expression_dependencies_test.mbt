///|
test "current expression references reach both inherited and replacement contracts" {
  let root = expression_contract_body(
    "sha256:72941beeddd533031e11992f8e367a4754105337658d0c7ff63127a76421fa4e",
  ).unwrap()
  assert_eq(root, ExpressionRoot)
  let pending = [root]
  let seen : Array[ExpressionContractBody] = []
  let mut edges = 0
  while pending.pop() is Some(body) {
    if seen.contains(body) {
      continue
    }
    seen.push(body)
    assert_eq(
      expression_contract_body(expression_contract_body_cid(body)),
      Some(body),
    )
    let count = expression_contract_dependency_count(body)
    for i in 0..<count {
      let edge = expression_contract_dependency_at(body, i).unwrap()
      assert_true(edge.pointer.has_prefix("/"))
      pending.push(edge.target)
      edges += 1
    }
    for invalid in [-2147483648, -1, count, 2147483647] {
      assert_true(expression_contract_dependency_at(body, invalid) is None)
    }
  }
  assert_eq(seen.length(), 15)
  assert_eq(edges, 16)
  assert_true(seen.contains(Inherited(RegexAst)))
  assert_true(seen.contains(RegexRepresentationSchema))
  assert_true(
    expression_contract_body_cid(Inherited(RegexAst)) !=
    expression_contract_body_cid(RegexRepresentationSchema),
  )
  assert_eq(expression_contract_dependency_count(ConsumerCapacity), 0)
}

///|
test "current expression edges retain exact declared reference positions and pins" {
  let regex = expression_contract_dependency_at(ExpressionRoot, 1).unwrap()
  assert_eq(regex.pointer, "/regex_ast_contract/cid")
  assert_eq(regex.target, RegexRepresentation)
  assert_eq(
    expression_contract_body_cid(regex.target),
    "sha256:9c4e0107ad1e6a1eb374e8365c07615c74773416b0b43f9a1e02db5e551efc78",
  )
  let schema = expression_contract_dependency_at(regex.target, 0).unwrap()
  assert_eq(schema.pointer, "/schema/cid")
  assert_eq(
    expression_contract_body_cid(schema.target),
    "sha256:cc114653eb3db3bdf94bf233f34c0baa5f4c5bc305aeb07ed66283706054d3d9",
  )
  let capacity = expression_contract_dependency_at(ExpressionRoot, 2).unwrap()
  assert_eq(capacity.pointer, "/laws/consumer_capacity_contract_cid")
  assert_eq(
    expression_contract_body_cid(capacity.target),
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
  )
  for
    unknown in [
      "", "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe72710",
    ] {
    assert_true(expression_contract_body(unknown) is None)
  }
}
