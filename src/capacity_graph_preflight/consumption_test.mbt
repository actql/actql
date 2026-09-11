///|
test "complete Graph preflight rejects valid limits without consumers" {
  let policy = policy(false)
  let pipeline = fixture_pipeline(false)
  let claims = sources(8, policy)
  let partial = @capacity_graph_preflight.check(
    pipeline,
    claims,
    policy,
    caps(),
  ).unwrap()
  assert_eq(@capacity_graph_preflight.unconsumed_limit_count(partial), 2)
  assert_true(
    @capacity_graph_preflight.check_complete(pipeline, claims, policy, caps())
    is Err(UnconsumedLimits(2)),
  )
  let (work, names) = @capacity_graph_preflight.usage(partial)
  assert_true(
    @capacity_graph_preflight.check_complete(pipeline, claims, policy, {
      max_work: work - 1,
      max_name_bytes: names,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_graph_preflight.check_complete(pipeline, claims, policy, {
      max_work: work,
      max_name_bytes: names,
    })
    is Err(UnconsumedLimits(2)),
  )
  // A consumer that is required but missing still fails before completeness.
  assert_true(
    @capacity_graph_preflight.check_complete(
      fixture_pipeline(true),
      claims,
      policy,
      caps(),
    )
    is Err(MissingMeasure(0, Nodes)),
  )
}
