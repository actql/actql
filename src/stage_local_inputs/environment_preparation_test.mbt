///|
test "Local continuation retains the same Source and members through ordered original steps" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("t", "b", schema_fields()),
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentPhase::LocalEnvironmentIndex,
  )
  assert_true(local_environment_preparation_usage(read) is None)
  assert_true(take_local_environment_preparation_result(read) is None)
  for
    expected in [
      LocalEnvironmentPhase::LocalEnvironmentGroups,
      LocalEnvironmentPhase::LocalEnvironmentSnapshot,
      LocalEnvironmentPhase::LocalEnvironmentSnapshot,
      LocalEnvironmentPhase::LocalEnvironmentDeclaration,
      LocalEnvironmentPhase::LocalEnvironmentReconciliation,
      LocalEnvironmentPhase::LocalEnvironmentDeclaration,
      LocalEnvironmentPhase::LocalEnvironmentReconciliation,
      LocalEnvironmentPhase::LocalEnvironmentAssembly,
      LocalEnvironmentPhase::LocalEnvironmentComplete,
    ] {
    assert_eq(advance_local_environment_preparation(read), expected)
  }
  assert_true(local_environment_preparation_failure_phase(read) is None)
  let recorded = local_environment_preparation_usage(read).unwrap()
  assert_true(
    recorded.work > 0 && recorded.nodes > 0 && recorded.text_bytes > 0,
  )
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentComplete,
  )
  let result = take_local_environment_preparation_result(read).unwrap().unwrap()
  assert_true(physical_equal(environment_program(result), source))
  assert_true(physical_equal(program_environment(result), environment))
  assert_eq(program_environment_usage(result), recorded)
  for i in 0..<2 {
    let stage = program_environment_stage(result, i).unwrap()
    assert_true(physical_equal(input_environment(stage), environment))
    assert_eq(snapshot_count(environment_assertions(stage)), 1)
  }
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentPhase::LocalEnvironmentTransferred,
  )
  assert_true(local_environment_preparation_usage(read) is None)
  assert_true(take_local_environment_preparation_result(read) is None)
  clear_local_environment_preparation(read)
  clear_local_environment_preparation(read)
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentTransferred,
  )
  assert_eq(local_environment_preparation_initial_construction_extent(), {
    record_headers: 5L,
    reference_slots: 20L,
    scalar_words: 11L,
  })
}

///|
test "Local continuation preserves typed snapshot failure without a zero usage observation" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("missing", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentGroups,
  )
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentSnapshot,
  )
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentFailed,
  )
  assert_eq(
    local_environment_preparation_failure_phase(read),
    Some(LocalEnvironmentPhase::LocalEnvironmentSnapshot),
  )
  assert_true(local_environment_preparation_usage(read) is None)
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentFailed,
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(UnknownStage(0, "missing"))),
  )
  assert_eq(
    local_environment_preparation_failure_phase(read),
    Some(LocalEnvironmentPhase::LocalEnvironmentSnapshot),
  )
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentPhase::LocalEnvironmentTransferred,
  )
  assert_true(take_local_environment_preparation_result(read) is None)
}

///|
test "Local continuation keeps earlier stages when original later reconciliation refuses" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "missing", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  for
    expected in [
      LocalEnvironmentPhase::LocalEnvironmentGroups,
      LocalEnvironmentPhase::LocalEnvironmentSnapshot,
      LocalEnvironmentPhase::LocalEnvironmentSnapshot,
      LocalEnvironmentPhase::LocalEnvironmentDeclaration,
      LocalEnvironmentPhase::LocalEnvironmentReconciliation,
      LocalEnvironmentPhase::LocalEnvironmentDeclaration,
      LocalEnvironmentPhase::LocalEnvironmentReconciliation,
      LocalEnvironmentPhase::LocalEnvironmentFailed,
    ] {
    assert_eq(advance_local_environment_preparation(read), expected)
  }
  assert_eq(
    local_environment_preparation_failure_phase(read),
    Some(LocalEnvironmentPhase::LocalEnvironmentReconciliation),
  )
  assert_true(local_environment_preparation_usage(read) is None)
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentPhase::LocalEnvironmentFailed,
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Environment(1, _))),
  )
  assert_true(take_local_environment_preparation_result(read) is None)
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentPhase::LocalEnvironmentTransferred,
  )
}

///|
test "Local continuation clear retires only untaken original aliases at real phase boundaries" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("t", "b", schema_fields()),
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  // Before index, after one original snapshot and with pending Prepared.
  for steps in [0, 3, 5] {
    let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
    for _ in 0..<steps {
      let _ = advance_local_environment_preparation(read)
    }
    assert_true(local_environment_preparation_usage(read) is None)
    clear_local_environment_preparation(read)
    clear_local_environment_preparation(read)
    assert_eq(
      local_environment_preparation_phase(read),
      LocalEnvironmentPhase::LocalEnvironmentRetired,
    )
    assert_eq(
      advance_local_environment_preparation(read),
      LocalEnvironmentPhase::LocalEnvironmentRetired,
    )
    assert_true(take_local_environment_preparation_result(read) is None)
  }
}
