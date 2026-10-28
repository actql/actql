///|
test "Context finish consumes the same partially advanced topology rather than preparing a second original" {
  let (views, locals, _) = original_context_input_fixture()
  let limits = local_program_context_source_limits()
  let (wired, _) = prepare_sourceview_program(views, locals, limits).unwrap()
  let bound = @stage_results.bind_prepared_program(wired, None, limits).unwrap()
  let materials = capacity_materials_fixture(bound).0
  let original = prepare_sourceview_context_input(
    views,
    locals,
    limits,
    local_context_limits(),
  ).unwrap()
  let read = begin_sourceview_context_topology_read(original).unwrap()
  assert_eq(@stage_results.advance_local_program_read(read), Imports)
  assert_eq(@stage_results.local_program_read_stage_index(read), Some(0))
  assert_true(
    physical_equal(
      begin_sourceview_context_topology_read(original).unwrap(),
      read,
    ),
  )
  let completed = prepare_sourceview_context_from_input(
    original,
    None,
    materials,
  ).unwrap()
  assert_eq(@stage_results.local_program_read_phase(read), Taken)
  assert_true(sourceview_context_topology_read(original) is None)
  assert_true(
    begin_sourceview_context_topology_read(original)
    is Err(Program(Unavailable)),
  )
  let direct = prepare_sourceview_context(
    views,
    locals,
    None,
    materials,
    limits,
    local_context_limits(),
  ).unwrap()
  assert_eq(selected_policy_usage(completed), selected_policy_usage(direct))
  assert_eq(
    program_identity_definition_cid(prepared_selected_identity(completed)),
    program_identity_definition_cid(prepared_selected_identity(direct)),
  )
}

///|
test "original Context preserves exact topology entry refusal and never restarts a cleared reader" {
  let (views, locals, _) = original_context_input_fixture()
  let limits = local_program_context_source_limits()
  let invalid = prepare_sourceview_context_input(
    views,
    locals,
    { ..limits, max_stages: 0, },
    local_context_limits(),
  ).unwrap()
  assert_true(
    begin_sourceview_context_topology_read(invalid)
    is Err(Program(Program(BudgetExceeded))),
  )
  assert_true(
    begin_sourceview_context_topology_read(invalid)
    is Err(Program(Program(BudgetExceeded))),
  )
  assert_true(sourceview_context_topology_read(invalid) is None)
  let original = prepare_sourceview_context_input(
    views,
    locals,
    limits,
    local_context_limits(),
  ).unwrap()
  let read = begin_sourceview_context_topology_read(original).unwrap()
  @stage_results.clear_local_program_read(read)
  assert_true(
    physical_equal(
      begin_sourceview_context_topology_read(original).unwrap(),
      read,
    ),
  )
  assert_true(
    prepare_sourceview_context_from_input(original, None, [])
    is Err(Program(Unavailable)),
  )
  retire_sourceview_context_input(original)
  assert_true(
    begin_sourceview_context_topology_read(original)
    is Err(Program(Unavailable)),
  )
}
