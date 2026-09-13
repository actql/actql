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
