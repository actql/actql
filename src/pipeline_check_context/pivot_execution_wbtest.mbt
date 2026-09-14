///|
test "pivot execution checks reject mismatched occurrence coordinates" {
  let pipeline = @pipeline.check_with_evidence(
    asof_test_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"kind\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"}, {\"pivot\":{\"index\":[\"id\",\"id\"],\"column\":\"kind\",\"values\":[\"b\",\"a\"],\"value\":\"id\",\"aggregate\":\"min\"}}]",
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
  assert_eq(@pipeline.operation_obligations_count(obligations), 3)
  for index in 0..<3 {
    let site : OperationRequirementSite = {
      stage: 2,
      producer_visit: 3,
      step: 1,
      group: 0,
      index,
      pipeline,
      obligations,
      requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
    }
    guard pivot_execution_check(site) is Ok(Some(PivotExecution(check))) else {
      fail("missing pivot execution")
    }
    assert_true(physical_equal(check.site, site))
    assert_true(physical_equal(check.step, step))
    assert_eq(check.input, @pipeline.Step(0))
    for
      bad in [
        { ..site, group: 1, },
        { ..site, index: 2147483647, },
        { ..site, index: (index + 1) % 3, },
      ] {
      assert_true(pivot_execution_check(bad) is Err(ForeignOccurrence(_)))
    }
    guard direct_execution_candidate(
        site,
        sequence_limit_policy(false),
        Ok(None),
        Ok(None),
      )
      is Ok(Some(PivotExecution(retained))) else {
      fail("pivot dispatch missing")
    }
    assert_true(physical_equal(retained.pivot, check.pivot))
  }
}
