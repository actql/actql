///|
test "direct execution selection stops on the first match or error" {
  let pipeline = @pipeline.check_with_evidence(
    asof_test_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"append\":{\"with\":\"seed\"}}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 2,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let step = @pipeline.step_at(pipeline, 1).unwrap()
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  let policy = sequence_limit_policy(false)
  for index in 0..<@pipeline.operation_obligations_count(obligations) {
    let site : OperationRequirementSite = {
      stage: 0,
      producer_visit: 0,
      step: 1,
      group: 0,
      index,
      pipeline,
      obligations,
      requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
    }
    guard direct_execution_candidate(
        site,
        policy,
        Err(BudgetExceeded),
        Err(ForeignOccurrence(99)),
      )
      is Ok(Some(AppendRows(check))) else {
      fail("later errors replaced an earlier match")
    }
    assert_true(physical_equal(check.site, site))
    assert_true(
      direct_execution_candidate(
        { ..site, step: 0, },
        policy,
        Err(BudgetExceeded),
        Err(ForeignOccurrence(99)),
      )
      is Err(ForeignOccurrence(0)),
    )
    let unrelated = {
      ..site,
      requirement: @pipeline.SeriesRequirement(ValidateRange),
    }
    assert_true(
      direct_execution_candidate(unrelated, policy, Ok(None), Ok(None))
      is Ok(None),
    )
    assert_true(
      direct_execution_candidate(
        unrelated,
        policy,
        Err(BudgetExceeded),
        Err(ForeignOccurrence(99)),
      )
      is Err(BudgetExceeded),
    )
    assert_true(
      direct_execution_candidate(
        unrelated,
        policy,
        Ok(None),
        Err(ForeignOccurrence(99)),
      )
      is Err(ForeignOccurrence(99)),
    )
  }
}
