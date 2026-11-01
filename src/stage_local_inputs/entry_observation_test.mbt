///|
test "original Local entry observes only charged initial work and keeps all early refusals" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("t", "b", schema_fields()),
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  // Exactly two Stage groups, two members and the original entrance charge.
  let (result, spent) = observe_begin_local_environment_preparation(
    source,
    environment,
    { ..caps(), max_work: 5, },
  )
  let read = result.unwrap()
  assert_eq(spent, 5)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentPhase::LocalEnvironmentIndex,
  )
  assert_true(local_environment_preparation_index_usage(read) is None)
  assert_true(local_environment_preparation_usage(read) is None)
  clear_local_environment_preparation(read)
  let (short, spent) = observe_begin_local_environment_preparation(
    source,
    environment,
    { ..caps(), max_work: 4, },
  )
  assert_true(short is Err(BudgetExceeded))
  assert_eq(spent, 0)
  let (invalid, spent) = observe_begin_local_environment_preparation(
    source,
    environment,
    { ..caps(), max_depth: -1, },
  )
  assert_true(invalid is Err(InvalidLimits))
  assert_eq(spent, 0)
  let foreign = @sourceviews.collect(two_stage_source(), {
    max_work: 10000,
    max_order_keys: 100,
  }).unwrap()
  let (invalid, spent) = observe_begin_local_environment_preparation(
    source,
    environment,
    caps(),
    sourceviews=Some(foreign),
  )
  assert_true(invalid is Err(ForeignSourceViews))
  assert_eq(spent, 0)
}
