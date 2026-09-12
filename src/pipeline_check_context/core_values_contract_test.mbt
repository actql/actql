///|
test "values count bodies retain occurrence ownership and share only body storage" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}}]
    ),
  )
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let limits : CoreContractLimits = {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }
  let inventory = collect_core_contracts(identity, limits).unwrap()
  let mut occurrences = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    if root.site is OperationCountLaw(stage, visit, step) {
      assert_eq(root.body, ValuesCountLaw)
      assert_true(
        @pipeline.step_at(
          program_identity_producer_at(identity, stage, visit).unwrap(),
          step,
        ).unwrap().operation
        is @pipeline.Values(_),
      )
      occurrences += 1
    }
  }
  assert_true(occurrences > 1)
  let mut bodies = 0
  for i in 0..<core_contract_body_count(inventory) {
    if core_contract_body_at(inventory, i) == Some(ValuesCountLaw) {
      bodies += 1
    }
  }
  assert_eq(bodies, 1)
  assert_eq(
    core_contract_cid(ValuesCountLaw),
    "sha256:0e0f9b4b6585ab7b17bafe484e82f44cd8f3acc9eec5ef9329cea200237a7971",
  )
  for stage in 0..<core_contract_stage_count(inventory) {
    let mut owns = false
    for i in 0..<core_contract_root_count(inventory) {
      if core_contract_root_at(inventory, i).unwrap().site
        is OperationCountLaw(s, _, _) &&
        s == stage {
        owns = true
      }
    }
    assert_eq(stage_has_contract(inventory, stage, ValuesCountLaw), owns)
  }
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
  assert_true(
    collect_core_contracts(identity, {
      ..exact,
      max_roots: exact.max_roots - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_core_contracts(identity, {
      ..exact,
      max_bodies: exact.max_bodies - 1,
    })
    is Err(BudgetExceeded),
  )
  let (without, _, _) = prepared_identity_fixture()
  let absent = collect_core_contracts(without, limits).unwrap()
  for stage in 0..<core_contract_stage_count(absent) {
    assert_false(stage_has_contract(absent, stage, ValuesCountLaw))
  }
}
