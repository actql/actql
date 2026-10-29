///|
test "Local reference quote is retained once for each same original captured member" {
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(
    two_stage_source(),
    environment,
    caps(),
  ).unwrap()
  assert_true(
    local_environment_snapshot_reference_inspection_bound(read) is None,
  )
  assert_true(
    observe_local_environment_snapshot_reference_construction(read) is None,
  )
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  let mut previous : (@source_ref.ReferenceReadConstructionInventory?, Int64)? = None
  for _ in 0..<2 {
    assert_true(
      local_environment_snapshot_reference_inspection_bound(read) is None,
    )
    assert_true(local_environment_snapshot_reference_construction(read) is None)
    let _ = observe_local_environment_snapshot_construction(read).unwrap()
    let bound = local_environment_snapshot_reference_inspection_bound(read).unwrap()
    let first = observe_local_environment_snapshot_reference_construction(read)
    let (recipe, work) = first.unwrap()
    assert_eq(recipe.unwrap().retained_utf16_units, 32L)
    assert_true(work > 0L && work <= bound)
    assert_true(
      physical_equal(
        first,
        observe_local_environment_snapshot_reference_construction(read),
      ),
    )
    assert_true(
      physical_equal(
        first,
        local_environment_snapshot_reference_construction(read),
      ),
    )
    if previous is Some(_) {
      assert_false(physical_equal(first, previous))
    }
    previous = first
    let _ = advance_local_environment_preparation(read)
    assert_true(local_environment_snapshot_reference_construction(read) is None)
  }
  assert_true(
    observe_local_environment_snapshot_reference_construction(read) is None,
  )
  clear_local_environment_preparation(read)
  assert_true(local_environment_snapshot_reference_construction(read) is None)
}

///|
test "Local failed member keeps its same quote until the explicit alias cut" {
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(
    two_stage_source(),
    environment,
    { ..caps(), max_nodes: 8, },
  ).unwrap()
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  let _ = observe_local_environment_snapshot_construction(read).unwrap()
  let observed = observe_local_environment_snapshot_reference_construction(read)
  assert_true(observed is Some((Some(_), _)))
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentFailed)
  assert_true(
    physical_equal(
      observed,
      local_environment_snapshot_reference_construction(read),
    ),
  )
  assert_true(
    observe_local_environment_snapshot_reference_construction(read) is None,
  )
  assert_true(
    take_local_environment_preparation_result(read)
    is Some(Err(Snapshot(0, BudgetExceeded))),
  )
  assert_true(
    physical_equal(
      observed,
      local_environment_snapshot_reference_construction(read),
    ),
  )
  clear_local_environment_preparation(read)
  assert_true(local_environment_snapshot_reference_construction(read) is None)
}
