///|
test "formal check closes consumed assertions through Result publication" {
  for body in ["{\"where\":\"id = id\"}", "{\"unique_by\":[\"id\"]}"] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      second_steps="[{\"assert_rows\":" + body + ",\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let program = checked[0]
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut consumed = 0
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      match @context.operation_closure_at(closure, i) {
        Some(StaticResolution(AssertionConsumption(link))) => {
          assert_true(
            physical_equal(
              @publication.pipeline(link.results),
              link.site.pipeline,
            ),
          )
          consumed += 1
        }
        Some(ExecutionCheck(RowAssertion(check))) => {
          assert_eq(check.site.step, 0)
          checks += 1
        }
        _ => ()
      }
    }
    assert_true(consumed > 0)
    assert_eq(consumed, checks)
    for
      steps in [
        "[{\"assert_rows\":" + body + ",\"as\":\"discarded\"}]",
        "[{\"assert_rows\":" +
        body +
        "},{\"select\":[\"id\"],\"as\":\"discarded\"}]",
      ] {
      try
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          second_stage=true,
          through_check=true,
          second_steps=steps,
          extra_step_budget=2,
        )
      catch {
        Closure(UnresolvedOperation(site)) => {
          guard site.requirement is @pipeline.RelationRequirement(pending) else {
            fail("wrong unresolved requirement")
          }
          assert_eq(pending.kind, @relation.AssertionConsumption)
        }
        error => raise error
      } noraise {
        _ => fail("unconsumed assertion escaped closure")
      }
    }
  }
}

///|
test "assertion consumption follows either binary input and shared producers" {
  for operand in ["rows", "again"] {
    for assertion_on_left in [false, true] {
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        second_steps="[{\"from\":\"" +
          operand +
          "\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"verified\"},{\"from\":\"" +
          (if assertion_on_left { "verified" } else { "rows" }) +
          "\",\"append\":{\"with\":\"" +
          (if assertion_on_left { "rows" } else { "verified" }) +
          "\"},\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=2,
      )
      let program = checked[0]
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut found = false
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(StaticResolution(AssertionConsumption(link))) {
          assert_eq(link.site.step, 0)
          assert_true(
            physical_equal(
              link.site.pipeline,
              unit_pipeline(program, 1).unwrap(),
            ),
          )
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
test "SourceView assertions retain acquisition checks and predicate policy" {
  for
    body in [
      "{\"where\":\"id = id\"}", "{\"where\":\"id > 0\"}", "{\"unique_by\":[\"id\"]}",
    ] {
    let program = checked_direct_program_fixture(assertion_body=body)
    assert_eq(source_execution_count(program), 5)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    let predicates = if body.contains("where") { 1 } else { 0 }
    assert_eq(publication_policy_predicate_count(policy), predicates)
    if predicates == 1 {
      let predicate = publication_policy_predicate_at(policy, 0).unwrap()
      assert_eq(predicate.step, 0)
      assert_eq(predicate.unknown_provenance, body.contains(">"))
    }
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(RowAssertion(check))) {
        assert_eq(check.input, @pipeline.Input(0))
        assert_true(
          physical_equal(
            check.site.pipeline,
            unit_pipeline(program, 0).unwrap(),
          ),
        )
        checks += 1
      }
    }
    assert_eq(checks, 1)
  }
}
