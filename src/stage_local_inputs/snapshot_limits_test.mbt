///|
test "Local snapshot binds original remaining limits once per actual member" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_true(local_environment_snapshot_construction_limits(read) is None)
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  let _ = observe_local_environment_snapshot_construction(read).unwrap()
  let first = local_environment_snapshot_construction_limits(read).unwrap()
  assert_eq(first.max_bytes, caps().max_text_bytes)
  assert_eq(first.max_nodes, caps().max_nodes)
  assert_eq(first.max_depth, caps().max_depth)
  let _ = observe_local_environment_snapshot_construction(read).unwrap()
  assert_true(
    physical_equal(
      first,
      local_environment_snapshot_construction_limits(read).unwrap(),
    ),
  )
  assert_true(local_environment_preparation_snapshot_emission(read) is None)
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentSnapshot,
  )
  assert_true(local_environment_snapshot_construction_limits(read) is None)
  let _ = observe_local_environment_snapshot_construction(read).unwrap()
  let second = local_environment_snapshot_construction_limits(read).unwrap()
  assert_false(physical_equal(first, second))
  assert_true(second.max_bytes < first.max_bytes)
  assert_true(second.max_nodes < first.max_nodes)
  assert_eq(second.max_depth, first.max_depth)
  let _ = advance_local_environment_preparation(read)
  assert_true(local_environment_snapshot_construction_limits(read) is None)
  clear_local_environment_preparation(read)
}

///|
test "Local failed member preserves selected limits and original refusal until clear" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, {
    ..caps(),
    max_nodes: 8,
  }).unwrap()
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  let _ = observe_local_environment_snapshot_construction(read).unwrap()
  let limits = local_environment_snapshot_construction_limits(read).unwrap()
  assert_eq(limits.max_nodes, 8)
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentFailed)
  assert_true(
    physical_equal(
      limits,
      local_environment_snapshot_construction_limits(read).unwrap(),
    ),
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Snapshot(0, BudgetExceeded))),
  )
  assert_true(
    physical_equal(
      limits,
      local_environment_snapshot_construction_limits(read).unwrap(),
    ),
  )
  clear_local_environment_preparation(read)
  assert_true(local_environment_snapshot_construction_limits(read) is None)
}
