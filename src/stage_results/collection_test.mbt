///|
test "collect existing Results without reissuing publication owners" {
  let operations = prepared("{\"from\":\"rows\",\"fields\":[\"amount\"]}")
  let original = check(operations, limits()).unwrap()
  let stages = [stage_at(original, 0).unwrap(), stage_at(original, 1).unwrap()]
  let used = usage(original)
  let exact : CollectionLimits = {
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_results: used.results,
  }
  let collected = collect_checked(operations, stages, exact).unwrap()
  assert_eq(usage(collected), used)
  assert_true(physical_equal(stage_at(collected, 0).unwrap(), stages[0]))
  assert_true(physical_equal(stage_at(collected, 1).unwrap(), stages[1]))
  assert_true(
    collect_checked(operations, [stages[0]], exact) is Err(StageCountMismatch),
  )
  assert_true(
    collect_checked(operations, [stages[1], stages[0]], exact)
    is Err(ForeignPipeline(0)),
  )
  for
    caps in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_results: exact.max_results - 1, },
    ] {
    assert_true(
      collect_checked(operations, stages, caps) is Err(BudgetExceeded(1)),
    )
  }
  assert_true(
    collect_checked(operations, stages, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
  // Same pipeline, but another stage's source Results, is not the declared map.
  let replacement = @results.check(
    @results.pipeline(stages[0]),
    @results.source(stages[1]),
    limits(),
  ).unwrap()
  assert_true(
    collect_checked(operations, [replacement, stages[1]], exact)
    is Err(ForeignResults(0)),
  )
  let retained = stages[1]
  stages.clear()
  assert_true(physical_equal(stage_at(collected, 1).unwrap(), retained))
}
