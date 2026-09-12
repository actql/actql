///|
test "Program operation requirements retain unused steps repeated producers and exact owners" {
  let steps =
    #|[{"derive":{"x":"concat($p, to_string($n))"}},{"dedupe_rows":{"by":["id","id"],"order_by":[{"id":"asc"}]}}]
  let (operations, references, bindings) = program_sources_fixture(
    steps=Some(steps),
  )
  let identity = identify_program_sources(
    bind_program_sources(operations, references, bindings, 10000000).unwrap(),
    identity_limits(),
  ).unwrap()
  let expressions = close_program_expressions(identity, 10000000, 100).unwrap()
  let inventory = collect_program_operation_requirements(
    expressions, 10000000, 100,
  ).unwrap()
  assert_true(
    physical_equal(operation_requirements_expressions(inventory), expressions),
  )
  let stages = program_reference_stages(references)
  let mut offset = 0
  for (stage, visit) in [(0, 0), (1, 0), (1, 1)] {
    let owner = @parameter_slots.pipeline(
      parameter_visit_at(stage_context_at(stages, stage).unwrap(), visit).unwrap().collected,
    )
    // Each producer retains the top-tie requirement of its unused dedupe step.
    for index in 0..<1 {
      let site = operation_requirements_at(inventory, offset).unwrap()
      assert_eq(
        (site.stage, site.producer_visit, site.step, site.group, site.index),
        (stage, visit, 1, 0, index),
      )
      assert_true(physical_equal(site.pipeline, owner))
      assert_eq(@pipeline.operation_obligations_scope(site.obligations), Body)
      guard site.requirement is @pipeline.RelationRequirement(v) else {
        abort("relation")
      }
      assert_eq(v.kind, FailOnTopTie)
      offset += 1
    }
  }
  let count = operation_requirements_count(inventory)
  assert_eq(count, 3)
  let work = operation_requirements_work(inventory)
  // Factory, two stages, three visits, six steps, six groups, three entries.
  assert_eq(work, expression_closure_work(expressions) + 1 + 2 + 3 + 6 + 6 + 3)
  assert_true(
    collect_program_operation_requirements(expressions, work, count) is Ok(_),
  )
  assert_true(
    collect_program_operation_requirements(expressions, work - 1, count)
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_program_operation_requirements(expressions, work, count - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_program_operation_requirements(expressions, -1, count)
    is Err(InvalidLimits),
  )
  assert_true(
    collect_program_operation_requirements(expressions, work, -1)
    is Err(InvalidLimits),
  )
  for i in [-1, count, 2147483647] {
    assert_true(operation_requirements_at(inventory, i) is None)
  }
}

///|
test "zero operation requirements still charge traversal and retain the Program owner" {
  let identity = expression_closure_fixture("concat($p, to_string($n))")
  let expressions = close_program_expressions(identity, 10000000, 0).unwrap()
  let inventory = collect_program_operation_requirements(
    expressions, 10000000, 0,
  ).unwrap()
  assert_eq(operation_requirements_count(inventory), 0)
  assert_true(
    physical_equal(operation_requirements_expressions(inventory), expressions),
  )
  let work = operation_requirements_work(inventory)
  assert_eq(work, expression_closure_work(expressions) + 1 + 2 + 3 + 3 + 3)
  assert_true(
    collect_program_operation_requirements(expressions, work, 0) is Ok(_),
  )
  assert_true(
    collect_program_operation_requirements(expressions, work - 1, 0)
    is Err(BudgetExceeded),
  )
}
