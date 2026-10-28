///|
test "Local index work envelope uses its original captured limits and survives no second phase" {
  for (maximum, remaining) in [(9, 6), (8, 5)] {
    let source = two_stage_source()
    let (environment, _) = environment_for([])
    let read = begin_local_environment_preparation(source, environment, {
      ..caps(),
      max_work: maximum,
    }).unwrap()
    assert_true(local_environment_index_work_bound(read) is None)
    let metadata = observe_local_environment_index_construction(read)
    assert_true(metadata is Some(_))
    assert_eq(local_environment_index_work_bound(read), Some(remaining))
    assert_eq(observe_local_environment_index_construction(read), metadata)
    // Two Stages, three inputs and one import need six original index units.
    // The one-short call retains its actual partial five-unit observation.
    let phase = advance_local_environment_preparation(read)
    if remaining == 6 {
      assert_eq(phase, LocalEnvironmentGroups)
    } else {
      assert_eq(phase, LocalEnvironmentFailed)
    }
    let observed = local_environment_preparation_index_usage(read).unwrap()
    assert_eq(observed.work, remaining)
    assert_true(local_environment_index_work_bound(read) is None)
    clear_local_environment_preparation(read)
    assert_true(local_environment_index_work_bound(read) is None)
    assert_eq(local_environment_preparation_index_usage(read), Some(observed))
  }
}
