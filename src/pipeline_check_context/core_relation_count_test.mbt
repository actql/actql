///|
test "Relation count contracts retain local occurrences without replacing Values laws" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"}},{"derive":{}},{"rename":{}},{"drop":[]}]
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
  let mut bodies = 0
  for stage in 0..<program_identity_stage_count(identity) {
    let mut expected = false
    for visit in 0..<program_identity_producer_count(identity, stage).unwrap() {
      let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
      for step in 0..<@pipeline.step_count(pipeline) {
        let operation = @pipeline.step_at(pipeline, step).unwrap().operation
        let mut matches = 0
        for i in 0..<core_contract_root_count(inventory) {
          let root = core_contract_root_at(inventory, i).unwrap()
          if root.site == OperationRelationCountRules(stage, visit, step) {
            assert_eq(root.body, RelationCountRules)
            matches += 1
          }
        }
        if operation is @pipeline.Values(_) {
          assert_eq(matches, 0)
        } else {
          assert_true(operation is @pipeline.Unary(_))
          assert_eq(matches, 1)
          expected = true
          occurrences += 1
        }
      }
    }
    assert_eq(
      stage_has_contract(inventory, stage, RelationCountRules),
      expected,
    )
  }
  for i in 0..<core_contract_body_count(inventory) {
    if core_contract_body_at(inventory, i) == Some(RelationCountRules) {
      bodies += 1
    }
  }
  assert_true(occurrences >= 3)
  assert_eq(bodies, 1)
  assert_eq(
    core_contract_cid(RelationCountRules),
    "sha256:163a0d75d56310803ac755d5f4f02069f442651711209037d6e3f512954c97ab",
  )
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
}
