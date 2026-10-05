///|
test "property Delta cold base transfers its exact unused snapshot once" {
  for quantum in [1, 7, 64] {
    let base = delta_fixture_storage(false)
    let cold = prepare_apply_base_source(
      Stored(base),
      delta_fixture_limits(),
      storage_limits(),
      None,
      0,
    ).unwrap()
    let snapshot = cold.snapshot.unwrap()
    assert_true(
      start_apply_from_prepared_base(cold, delta_cursor("{}"))
      is Err(InvalidDelta),
    )
    assert_true(physical_equal(cold.snapshot.unwrap(), snapshot))
    assert_true(@storage.available(base))
    let active = start_apply_from_prepared_base(
      cold,
      delta_cursor(delta_fixture_expected()),
    ).unwrap()
    assert_true(physical_equal(active.snapshot_preparation.unwrap(), snapshot))
    assert_true(cold.snapshot is None && cold.source is None)
    assert_true(
      start_apply_from_prepared_base(
        cold,
        delta_cursor(delta_fixture_expected()),
      )
      is Err(Terminal),
    )
    cleanup_apply_base(cold)
    cleanup_apply_base(cold)
    let result = complete_apply(active, quantum)
    assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
    assert_true(cleanup_apply(active))
    assert_true(@storage.available(base))
    @storage.discard(result)
    @storage.discard(base)
  }
}

///|
test "property Delta cold base refuses combined workspace and preserves borrowed storage on cleanup" {
  let base = delta_fixture_storage(false)
  assert_true(
    prepare_apply_base_source(
      Stored(base),
      delta_fixture_limits(),
      storage_limits(),
      None,
      2147483647,
    )
    is Err(WorkspaceLimit),
  )
  assert_true(
    prepare_apply_base_source(
      Stored(base),
      delta_fixture_limits(),
      storage_limits(),
      None,
      -1,
    )
    is Err(InvalidLimits),
  )
  let cold = prepare_apply_base_source(
    Stored(base),
    delta_fixture_limits(),
    storage_limits(),
    None,
    0,
  ).unwrap()
  cleanup_apply_base(cold)
  cleanup_apply_base(cold)
  assert_true(cold.snapshot is None && cold.source is None)
  assert_true(@storage.available(base))
  assert_true(
    start_apply_from_prepared_base(cold, delta_cursor(delta_fixture_expected()))
    is Err(Terminal),
  )
  let revoked = prepare_apply_base_source(
    Stored(base),
    delta_fixture_limits(),
    storage_limits(),
    None,
    0,
  ).unwrap()
  @storage.discard(base)
  assert_true(
    start_apply_from_prepared_base(
      revoked,
      delta_cursor(delta_fixture_expected()),
    )
    is Err(InvalidGraph),
  )
  cleanup_apply_base(revoked)
}
