///|
test "Graph count contracts retain construction and row bridge occurrences" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},{"graph":{"nodes":{"from":"seed","id":"id","fields":[]},"edges":{"from":"seed","source":"id","target":"dst","fields":[]}},"as":"g"},{"node_rows":true}]
    ),
    sga=true,
  )
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let inventory = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  let mut roots = 0
  let mut bodies = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    if root.site is OperationGraphCountRules(stage, visit, step) {
      let operation = @pipeline.step_at(
          program_identity_producer_at(identity, stage, visit).unwrap(),
          step,
        ).unwrap().operation
      assert_true(
        operation is @pipeline.GraphConstruction(..) ||
        operation is @pipeline.Projection(_),
      )
      assert_eq(root.body, GraphCountRules)
      assert_true(stage_has_contract(inventory, stage, GraphCountRules))
      roots += 1
    }
  }
  for i in 0..<core_contract_body_count(inventory) {
    if core_contract_body_at(inventory, i) == Some(GraphCountRules) {
      bodies += 1
    }
  }
  assert_true(roots >= 2)
  assert_eq(bodies, 1)
  let exact : CoreContractLimits = {
    max_work: core_contract_usage(inventory).0,
    max_roots: core_contract_root_count(inventory),
    max_bodies: core_contract_body_count(inventory),
    max_edges: core_contract_usage(inventory).1,
  }
  assert_true(collect_core_contracts(identity, exact) is Ok(_))
  assert_true(
    collect_core_contracts(identity, { ..exact, max_work: exact.max_work - 1, })
    is Err(BudgetExceeded),
  )
}
