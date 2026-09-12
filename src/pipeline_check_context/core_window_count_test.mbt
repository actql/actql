///|
test "window count contract follows the owning Program operation" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},{"row_window":{"kind":"fixed","time":"id","size":10,"step":3}}]
    ),
    tea=true,
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
  let mut windows = 0
  for stage in 0..<program_identity_stage_count(identity) {
    let mut owned = false
    for visit in 0..<program_identity_producer_count(identity, stage).unwrap() {
      if program_identity_producer_is_local(identity, stage, visit) !=
        Some(true) {
        continue
      }
      let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
      for step in 0..<@pipeline.step_count(pipeline) {
        let expected = @pipeline.step_at(pipeline, step).unwrap().operation
          is @pipeline.Window(_)
        let mut roots = 0
        for i in 0..<core_contract_root_count(inventory) {
          let root = core_contract_root_at(inventory, i).unwrap()
          if root.site == OperationWindowCountRules(stage, visit, step) {
            assert_eq(root.body, WindowCountRules)
            roots += 1
          }
        }
        assert_eq(roots, if expected { 1 } else { 0 })
        if expected {
          owned = true
          windows += 1
        }
      }
    }
    assert_eq(stage_has_contract(inventory, stage, WindowCountRules), owned)
  }
  assert_true(windows > 0)
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
