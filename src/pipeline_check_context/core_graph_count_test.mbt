///|
test "Graph count contracts retain construction and row bridge occurrences" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"seed","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"},{"match_nodes":{"definition":"N","where":"true","fields":["id"]}}]
    ),
    property_graph=true,
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
        operation is @pipeline.PropertyGraphConstruction(..) ||
        operation is @pipeline.GraphMatch(_),
      )
      assert_eq(root.body, PropertyGraphCountRules)
      assert_true(stage_has_contract(inventory, stage, PropertyGraphCountRules))
      roots += 1
    }
  }
  for i in 0..<core_contract_body_count(inventory) {
    if core_contract_body_at(inventory, i) == Some(PropertyGraphCountRules) {
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
