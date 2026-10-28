///|
test "Local snapshot construction captures the same member geometry once before entry" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "b", schema_fields()),
  ])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_true(observe_local_environment_snapshot_construction(read) is None)
  for _ in 0..<2 {
    let _ = advance_local_environment_preparation(read)
  }
  for i in 0..<2 {
    let geometry = observe_local_environment_snapshot_construction(read)
    let observed = geometry.unwrap()
    assert_true(
      physical_equal(
        observe_local_environment_snapshot_construction(read),
        geometry,
      ),
    )
    let original_member = @environment.member_at(
      environment,
      SchemaSnapshots,
      i,
    ).unwrap()
    assert_eq(observed, @environment.member_emission_geometry(original_member))
    assert_eq(local_environment_snapshot_construction_geometry(read), geometry)
    let _ = advance_local_environment_preparation(read)
    let (at, emitted) = local_environment_preparation_snapshot_emission(read).unwrap()
    assert_eq(at, i)
    assert_eq(emitted, Some(observed))
    assert_true(local_environment_snapshot_construction_geometry(read) is None)
  }
  assert_true(observe_local_environment_snapshot_construction(read) is None)
  clear_local_environment_preparation(read)
  assert_true(local_environment_snapshot_construction_geometry(read) is None)
  assert_eq(local_environment_snapshot_construction_inspection_extent(), {
    record_headers: 8L,
    reference_slots: 9L,
    scalar_words: 12L,
  })
  assert_eq(local_environment_snapshot_construction_retained_extent(), {
    record_headers: 5L,
    reference_slots: 6L,
    scalar_words: 8L,
  })
  assert_eq(@environment.member_instance_construction_extent(), {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 2L,
  })
  assert_eq(local_environment_snapshot_construction_metadata_extent(), {
    record_headers: 4L,
    reference_slots: 4L,
    scalar_words: 6L,
  })
}

///|
test "Local failed snapshot keeps its captured member until original clear" {
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
  let geometry = observe_local_environment_snapshot_construction(read)
  assert_true(geometry is Some(_))
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentFailed)
  assert_true(observe_local_environment_snapshot_construction(read) is None)
  assert_true(
    physical_equal(
      local_environment_snapshot_construction_geometry(read),
      geometry,
    ),
  )
  let _ = take_local_environment_preparation_result(read).unwrap()
  assert_true(
    physical_equal(
      local_environment_snapshot_construction_geometry(read),
      geometry,
    ),
  )
  clear_local_environment_preparation(read)
  assert_true(local_environment_snapshot_construction_geometry(read) is None)
}

///|
test "Local captured original Member supplies text quantity before read and across failure" {
  let source = two_stage_source()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  for failed in [false, true] {
    let limits = if failed { { ..caps(), max_nodes: 8, } } else { caps() }
    let read = begin_local_environment_preparation(source, environment, limits).unwrap()
    assert_true(local_environment_snapshot_text_construction(read) is None)
    for _ in 0..<2 {
      let _ = advance_local_environment_preparation(read)
    }
    assert_true(local_environment_snapshot_text_construction(read) is None)
    let _ = observe_local_environment_snapshot_construction(read).unwrap()
    let original = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
    let quantity = local_environment_snapshot_text_construction(read).unwrap()
    assert_eq(
      quantity,
      @environment.member_text_emission_construction_extent(original),
    )
    let _ = advance_local_environment_preparation(read)
    if failed {
      assert_eq(
        local_environment_preparation_phase(read),
        LocalEnvironmentFailed,
      )
      assert_eq(
        local_environment_snapshot_text_construction(read),
        Some(quantity),
      )
      let _ = take_local_environment_preparation_result(read).unwrap()
      assert_eq(
        local_environment_snapshot_text_construction(read),
        Some(quantity),
      )
    } else {
      assert_true(local_environment_snapshot_text_construction(read) is None)
    }
    clear_local_environment_preparation(read)
    assert_true(local_environment_snapshot_text_construction(read) is None)
    // A quantity retained by the caller is still its own DATA after clear.
    assert_eq(quantity.owned_wire_bytes, 0L)
    assert_true(quantity.owned_utf16_units > 0L)
  }
}
