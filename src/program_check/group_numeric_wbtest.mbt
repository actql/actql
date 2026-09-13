///|
test "decimal sum closes from source without borrowing the floating observation boundary" {
  for filter in ["", ",\"filter\":\"FALSE\""] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      producer_expression="CAST(id AS DECIMAL(4,2))",
      second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"sum\",\"field\":\"value\"" +
        filter +
        "}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let program = checked[0]
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut demands = 0
    let mut domains = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(GroupExecution(check))) else {
        continue
      }
      match check.rule {
        EvaluateAggregate(call) | ValidateResultContract(call) => {
          assert_eq(@relation.aggregate_function(call), @relation.Sum)
          assert_true(
            physical_equal(check.site.pipeline, program.units[1].pipeline),
          )
          assert_true(
            physical_equal(
              call,
              @relation.aggregate_for_validation(check.group, check.site.index).unwrap(),
            ),
          )
          assert_true(
            @relation.aggregate_result(call).shape is @contract.Decimal(..),
          )
          assert_eq(@relation.aggregate_filter(call) is Some(_), filter != "")
          if check.rule is EvaluateAggregate(_) {
            demands += 1
          } else {
            domains += 1
          }
        }
        PartitionGroups => ()
        _ => fail("exact decimal sum acquired an unrelated runtime law")
      }
    }
    assert_eq(demands, 1)
    assert_eq(domains, 1)
  }
}

///|
test "false filters and integral-looking numbers do not discharge sum or avg observations" {
  for function in ["sum", "avg"] {
    for filter in ["", ",\"filter\":\"FALSE\""] {
      let checked : Array[CheckedProgram] = []
      try
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          second_stage=true,
          through_check=true,
          checked_results=checked,
          producer_expression="1",
          second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"" +
            function +
            "\",\"field\":\"value\"" +
            filter +
            "}}},\"as\":\"selected\"}]",
          second_result_from="selected",
          extra_step_budget=2,
        )
      catch {
        Closure(UnresolvedOperation(site)) => {
          assert_eq(site.stage, 1)
          guard site.requirement is @pipeline.RelationRequirement(pending) else {
            fail("wrong requirement")
          }
          assert_eq(pending.kind, @relation.NumericAggregateObservation)
        }
        error => raise error
      } noraise {
        _ => fail("observation contract was bypassed")
      }
      assert_eq(checked.length(), 0)
    }
  }
}
