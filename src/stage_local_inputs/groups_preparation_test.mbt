///|
fn groups_preparation_source(json : String) -> @stages.Source {
  let program = @syntax.parse(
    json,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
test "Local groups quote the same Stage inventory and retain only new name work" {
  let source = two_stage_source()
  let (environment, _) = environment_for([])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_true(local_environment_groups_construction(read) is None)
  assert_true(local_environment_groups_work_bound(read) is None)
  assert_true(local_environment_preparation_groups_work(read) is None)
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentGroups)
  let inventory = local_environment_groups_construction(read).unwrap()
  // Index work is accounted in its own phase, not subtracted from this bound.
  assert_eq(
    local_environment_groups_work_bound(read),
    Some(caps().max_work - 3),
  )
  // Two actual Stages, all empty per-Stage Arrays up front, one outer Array.
  // The same no-member step also creates the empty successor Stage array.
  // Names and original Stage bodies are borrowed; each Map value is its index.
  assert_eq(inventory, {
    records: 5L,
    record_references: 4L,
    record_words: 5L,
    reference_arrays: 4L,
    reference_items: 2L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: 2L,
  })
  assert_eq(@shape.collection_construction_extent(inventory).unwrap(), {
    record_headers: 32L,
    reference_slots: 102L,
    scalar_words: 60L,
  })
  assert_eq(local_environment_groups_construction(read), Some(inventory))
  let index_usage = local_environment_preparation_index_usage(read).unwrap()
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentDeclaration,
  )
  assert_eq(local_environment_preparation_groups_work(read), Some(2))
  assert_true(local_environment_groups_work_bound(read) is None)
  assert_eq(local_environment_preparation_index_usage(read), Some(index_usage))
  assert_true(local_environment_groups_construction(read) is None)
  clear_local_environment_preparation(read)
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentRetired,
  )
  assert_eq(local_environment_preparation_groups_work(read), Some(2))
}

///|
test "Local groups preserve exact and one short ordered name charges on refusal" {
  let source = groups_preparation_source(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"a","inputs":{},"steps":[],"results":{"out":{}}},{"id":"longname","inputs":{},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"longname","result":"out"}}}}
    ),
  )
  let (environment, _) = environment_for([])
  // Original initial charge is Stages2 + members0 +1. Group names cost1+8.
  for
    (cap, expected, spent) in [
      (12, LocalEnvironmentPhase::LocalEnvironmentDeclaration, 9),
      (11, LocalEnvironmentPhase::LocalEnvironmentFailed, 1),
    ] {
    let read = begin_local_environment_preparation(source, environment, {
      ..caps(),
      max_work: cap,
    }).unwrap()
    assert_eq(
      advance_local_environment_preparation(read),
      LocalEnvironmentGroups,
    )
    assert_true(local_environment_preparation_groups_work(read) is None)
    assert_eq(local_environment_groups_work_bound(read), Some(cap - 3))
    assert_eq(advance_local_environment_preparation(read), expected)
    assert_eq(local_environment_preparation_groups_work(read), Some(spent))
    if expected == LocalEnvironmentFailed {
      assert_eq(
        local_environment_preparation_failure_phase(read),
        Some(LocalEnvironmentGroups),
      )
      assert_true(local_environment_preparation_usage(read) is None)
      assert_true(
        take_local_environment_preparation_result(read)
        is Some(Err(BudgetExceeded)),
      )
    }
    clear_local_environment_preparation(read)
    assert_eq(local_environment_preparation_groups_work(read), Some(spent))
    let _ = advance_local_environment_preparation(read)
    assert_eq(local_environment_preparation_groups_work(read), Some(spent))
  }
}

///|
test "Local groups distinguish unstarted from actual zero before the first name refusal" {
  let source = groups_preparation_source(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"longname","inputs":{},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"longname","result":"out"}}}}
    ),
  )
  let (environment, _) = environment_for([])
  let read = begin_local_environment_preparation(source, environment, {
    ..caps(),
    max_work: 3,
  }).unwrap()
  assert_true(local_environment_preparation_groups_work(read) is None)
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentGroups)
  assert_eq(
    local_environment_preparation_index_usage(read),
    Some({ work: 1, text_bytes: 8, }),
  )
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentFailed)
  assert_eq(local_environment_preparation_groups_work(read), Some(0))
  assert_true(local_environment_preparation_usage(read) is None)
  clear_local_environment_preparation(read)
  assert_eq(local_environment_preparation_groups_work(read), Some(0))
}

///|
test "Local groups with a member leave successor Stage storage to the snapshot phase" {
  let source = two_stage_source()
  let (environment, _) = environment_for([snapshot_for("b", schema_fields())])
  let read = begin_local_environment_preparation(source, environment, caps()).unwrap()
  assert_eq(advance_local_environment_preparation(read), LocalEnvironmentGroups)
  let inventory = local_environment_groups_construction(read).unwrap()
  assert_eq(inventory.records, 4L)
  assert_eq(inventory.record_references, 3L)
  assert_eq(inventory.record_words, 4L)
  assert_eq(inventory.reference_arrays, 3L)
  assert_eq(
    local_environment_groups_work_bound(read),
    Some(caps().max_work - 4),
  )
  let index = local_environment_preparation_index_usage(read)
  assert_eq(
    advance_local_environment_preparation(read),
    LocalEnvironmentSnapshot,
  )
  assert_eq(local_environment_preparation_groups_work(read), Some(2))
  assert_eq(local_environment_preparation_index_usage(read), index)
  clear_local_environment_preparation(read)
  assert_true(local_environment_groups_work_bound(read) is None)
}
