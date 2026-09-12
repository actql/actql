///|
test "transfer classification roots cover every owned step without merging visits" {
  let (identity, _, _) = prepared_identity_fixture()
  let limits : CoreContractLimits = {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }
  let inventory = collect_core_contracts(identity, limits).unwrap()
  let mut expected = 0
  for stage in 0..<program_identity_stage_count(identity) {
    let mut stage_steps = 0
    for visit in 0..<program_identity_producer_count(identity, stage).unwrap() {
      if program_identity_producer_is_local(identity, stage, visit) !=
        Some(true) {
        continue
      }
      let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
      for step in 0..<@pipeline.step_count(pipeline) {
        let mut matches = 0
        for i in 0..<core_contract_root_count(inventory) {
          let root = core_contract_root_at(inventory, i).unwrap()
          if root.site == OperationTransferRules(stage, visit, step) {
            assert_eq(root.body, BoundTransferRules)
            matches += 1
          }
        }
        assert_eq(matches, 1)
        stage_steps += 1
      }
    }
    expected += stage_steps
    assert_eq(
      stage_has_contract(inventory, stage, BoundTransferRules),
      stage_steps > 0,
    )
  }
  let mut roots = 0
  let mut bodies = 0
  for i in 0..<core_contract_root_count(inventory) {
    if core_contract_root_at(inventory, i).unwrap().site
      is OperationTransferRules(_, _, _) {
      roots += 1
    }
  }
  for i in 0..<core_contract_body_count(inventory) {
    if core_contract_body_at(inventory, i) == Some(BoundTransferRules) {
      bodies += 1
    }
  }
  assert_true(expected > 1)
  assert_eq(roots, expected)
  assert_eq(bodies, 1)
  let exact : CoreContractLimits = {
    max_work: core_contract_usage(inventory).0,
    max_roots: core_contract_root_count(inventory),
    max_bodies: core_contract_body_count(inventory),
    max_edges: core_contract_usage(inventory).1,
  }
  assert_true(collect_core_contracts(identity, exact) is Ok(_))
  assert_true(
    collect_core_contracts(identity, {
      ..exact,
      max_roots: exact.max_roots - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_core_contracts(identity, { ..exact, max_work: exact.max_work - 1, })
    is Err(BudgetExceeded),
  )
}
