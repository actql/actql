///|
test "Local snapshot emission binds each original member index and survives transfer" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_true(local_environment_preparation_snapshot_emission(read) is None)
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  for i in 0..<2 {
    assert_eq(
      local_environment_preparation_phase(read),
      LocalEnvironmentSnapshot,
    )
    let _ = advance_local_environment_preparation(read)
    let (at, used) = local_environment_preparation_snapshot_emission(read).unwrap()
    assert_eq(at, i)
    let entry = @environment.member_at(environment, SchemaSnapshots, i).unwrap()
    let (bytes, nodes) = @environment.member_usage(entry)
    let (charged_bytes, charged_nodes, depth) = used.unwrap()
    assert_eq((charged_bytes, charged_nodes), (bytes, nodes))
    assert_true(depth > 0)
  }
  let recorded = local_environment_preparation_snapshot_emission(read)
  let mut steps = 0
  while local_environment_preparation_phase(read) != LocalEnvironmentComplete {
    assert_true(steps < 20)
    let _ = advance_local_environment_preparation(read)
    steps += 1
  }
  let _ = take_local_environment_preparation_result(read).unwrap().unwrap()
  clear_local_environment_preparation(read)
  assert_eq(local_environment_preparation_snapshot_emission(read), recorded)
  assert_eq(local_environment_snapshot_emission_observation_extent(), {
    record_headers: 7L,
    reference_slots: 7L,
    scalar_words: 7L,
  })
}

///|
test "Local failed snapshot retains partial emission and no invented full usage" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  for node_limit in [8, 0] {
    let read = begin_local_environment_preparation(source, environment, {
      ..caps(),
      max_nodes: node_limit,
    }).unwrap()
    for _ in 0..<2 {
      let _ = advance_local_environment_preparation(read)
    }
    assert_eq(
      advance_local_environment_preparation(read),
      LocalEnvironmentFailed,
    )
    let recorded = local_environment_preparation_snapshot_emission(read).unwrap()
    assert_eq(recorded.0, 0)
    if node_limit == 0 {
      assert_true(recorded.1 is None)
    } else {
      let (bytes, nodes, _) = recorded.1.unwrap()
      assert_true(bytes > 0)
      assert_eq(nodes, node_limit)
    }
    assert_true(local_environment_preparation_usage(read) is None)
    assert_true(
      take_local_environment_preparation_result(read)
      is Some(Err(Snapshot(0, @snapshot.BudgetExceeded))),
    )
    clear_local_environment_preparation(read)
    assert_eq(
      local_environment_preparation_snapshot_emission(read),
      Some(recorded),
    )
  }
}
