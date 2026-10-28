///|
test "Local index construction keeps one original geometry limits and usage through transfer" {
  let source = two_stage_source()
  let (environment, _) = environment_for([])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_true(local_environment_preparation_index_usage(read) is None)
  let bound = local_environment_index_inspection_bound(read).unwrap()
  let work = observe_local_environment_index_construction(read).unwrap()
  assert_true(work > 0L && work <= bound)
  assert_eq(observe_local_environment_index_construction(read), Some(work))
  let quoted = local_environment_index_construction(read).unwrap()
  assert_eq(quoted.returned, {
    record_headers: 55L,
    reference_slots: 125L,
    scalar_words: 142L,
  })
  assert_eq(quoted.temporary, {
    record_headers: 101L,
    reference_slots: 204L,
    scalar_words: 238L,
  })
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentGroups)
  let used = local_environment_preparation_index_usage(read).unwrap()
  // Two Stage names, three input names and one import name are all1byte.
  // Work is Stages2 + inputs1+2 + imports1 =6, with no inherited prefix.
  assert_eq(used, { work: 6, text_bytes: 6, })
  assert_true(observe_local_environment_index_construction(read) is None)
  assert_true(local_environment_index_construction(read) is None)
  let mut steps = 0
  while local_environment_preparation_phase(read) != LocalEnvironmentComplete {
    assert_true(steps < 20)
    let _ = advance_local_environment_preparation(read)
    steps += 1
  }
  let result = take_local_environment_preparation_result(read).unwrap().unwrap()
  assert_true(physical_equal(environment_program(result), source))
  assert_eq(local_environment_preparation_index_usage(read), Some(used))
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_phase(read),
    LocalEnvironmentTransferred,
  )
  assert_eq(local_environment_preparation_index_usage(read), Some(used))
  assert_eq(local_environment_index_inspection_work(read), Some(work))
  assert_eq(local_environment_index_inspection_retained_extent(), {
    record_headers: 5L,
    reference_slots: 4L,
    scalar_words: 13L,
  })
}

///|
test "Local typed index refusal retains known observation and never fabricates whole usage" {
  let source = two_stage_source()
  let (environment, _) = environment_for([])
  let read = begin_local_environment_preparation(source, environment, {
    ..caps(),
    max_work: 3,
  }).unwrap()
  assert_true(local_environment_preparation_index_usage(read) is None)
  let work = observe_local_environment_index_construction(read).unwrap()
  assert_eq(work, 1L)
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentFailed)
  assert_eq(
    local_environment_preparation_index_usage(read),
    Some({ work: 0, text_bytes: 0, }),
  )
  assert_true(local_environment_preparation_usage(read) is None)
  assert_eq(
    local_environment_preparation_failure_phase(read),
    Some(LocalEnvironmentIndex),
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Index(@refs.BudgetExceeded))),
  )
  clear_local_environment_preparation(read)
  assert_eq(
    local_environment_preparation_index_usage(read),
    Some({ work: 0, text_bytes: 0, }),
  )
  assert_eq(local_environment_index_inspection_work(read), Some(1L))
}
