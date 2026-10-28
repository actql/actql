///|
test "Local member work observes each original step without recharging Index or earlier members" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_true(local_environment_snapshots_work_bound(read) is None)
  assert_eq(
    observe_advance_local_environment_snapshot(read),
    (LocalEnvironmentIndex, None),
  )
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  let start = local_environment_snapshots_work_bound(read).unwrap()
  let index = local_environment_preparation_index_usage(read)
  let mut total = 0
  for i in 0..<2 {
    let before = local_environment_snapshots_work_bound(read).unwrap()
    let original_member = @environment.member_at(
      environment,
      SchemaSnapshots,
      i,
    ).unwrap()
    let (_, nodes) = @environment.member_usage(original_member)
    let (phase, work) = observe_advance_local_environment_snapshot(read)
    // Authored Stage names are s/t, each one UTF16 unit.
    assert_eq(work, Some(nodes + 1))
    total += nodes + 1
    assert_eq(local_environment_preparation_index_usage(read), index)
    if i == 0 {
      assert_eq(phase, LocalEnvironmentSnapshot)
      assert_eq(
        local_environment_snapshots_work_bound(read),
        Some(before - nodes - 1),
      )
    } else {
      assert_eq(phase, LocalEnvironmentDeclaration)
      assert_true(local_environment_snapshots_work_bound(read) is None)
    }
  }
  assert_true(total <= start)
  assert_eq(
    observe_advance_local_environment_snapshot(read),
    (LocalEnvironmentDeclaration, None),
  )
  clear_local_environment_preparation(read)
  assert_eq(
    observe_advance_local_environment_snapshot(read),
    (LocalEnvironmentRetired, None),
  )
}

///|
test "Local member failure distinguishes actual zero debit from partial writer work" {
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
  let (phase, work) = observe_advance_local_environment_snapshot(read)
  assert_eq(phase, LocalEnvironmentFailed)
  assert_eq(work, Some(0))
  let (_, emitted) = local_environment_preparation_snapshot_emission(read).unwrap()
  assert_true(emitted is Some((_, 8, _)))
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Snapshot(0, @snapshot.BudgetExceeded))),
  )
  assert_eq(
    observe_advance_local_environment_snapshot(read),
    (LocalEnvironmentTransferred, None),
  )
  clear_local_environment_preparation(read)
}

///|
test "Local unknown Stage preserves the completed member and name debit before refusal" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("absent", "b", schema_fields()),
  ])
  let original_member = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let (_, nodes) = @environment.member_usage(original_member)
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  assert_eq(
    observe_advance_local_environment_snapshot(read),
    (LocalEnvironmentFailed, Some(nodes + 6)),
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(UnknownStage(0, "absent"))),
  )
  clear_local_environment_preparation(read)
}
