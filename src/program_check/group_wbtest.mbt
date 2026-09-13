///|
test "formal check closes exact groups after Result import" {
  for
    body in [
      "{\"by\":[\"id\",\"value\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}", "{\"by\":[],\"aggregates\":{\"id\":{\"fn\":\"count\"},\"value\":{\"fn\":\"max\",\"field\":\"value\"}}}",
    ] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      second_steps="[{\"group\":" + body + ",\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let program = checked[0]
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut partition = 0
    let mut demand = 0
    let mut result_contract = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(GroupExecution(check))) else {
        continue
      }
      assert_eq(check.site.stage, 1)
      match check.rule {
        PartitionGroups => partition += 1
        EvaluateAggregate(_) => demand += 1
        ValidateResultContract(_) => result_contract += 1
        EnforceArrayItems(_) => fail("unexpected array envelope")
        EnforceStatisticalLaw(_, _) => fail("unexpected statistical fold")
      }
    }
    assert_eq(partition, 1)
    assert_eq(demand, if body.contains("\"max\"") { 2 } else { 1 })
    assert_eq(result_contract, demand)
  }
}

///|
test "formal group retains unresolved floating observations instead of returning partial success" {
  let checked : Array[CheckedProgram] = []
  try
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"sum\",\"field\":\"value\"}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
  catch {
    Closure(UnresolvedOperation(site)) => {
      assert_eq(site.stage, 1)
      guard site.requirement is @pipeline.RelationRequirement(pending) else {
        fail("wrong unresolved requirement")
      }
      assert_eq(pending.kind, @relation.NumericAggregateObservation)
    }
    error => raise error
  } noraise {
    _ => fail("numeric observation was silently discharged")
  }
  assert_eq(checked.length(), 0)
}
