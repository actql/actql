///|
test "changes state uses the owned default mode and exact checkpoint contract" {
  let index = join_resolution_fixture(changes=true)
  let identity = expression_closure_identity(
    operation_requirements_expressions(operation_resolution_requirements(index)),
  )
  let limits : @snapshot.Limits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }
  let state = prepare_source_state_requirement(identity, 0, 0, limits)
    .unwrap()
    .unwrap()
  let (view, checkpoint) = changes_sourceview_pins()
  assert_true(physical_equal(state.identity, identity))
  assert_eq(state.stage_id, "s")
  assert_eq(state.input_name, "remote")
  assert_eq(state.source_view_cid, view)
  assert_eq(state.checkpoint_cid, checkpoint)
  let exact : @snapshot.Limits = {
    max_bytes: state.bytes,
    max_nodes: state.nodes,
    max_depth: 1,
  }
  assert_eq(
    prepare_source_state_requirement(identity, 0, 0, exact).unwrap().unwrap().cid,
    state.cid,
  )
  assert_true(
    prepare_source_state_requirement(identity, 0, 0, {
      ..exact,
      max_bytes: state.bytes - 1,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    prepare_source_state_requirement(identity, 0, 0, {
      ..exact,
      max_nodes: state.nodes - 1,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    prepare_source_state_requirement(identity, 0, 0, { ..exact, max_depth: 0, })
    is Err(Encoding(_)),
  )
  assert_true(
    prepare_source_state_requirement(identity, -1, 0, limits)
    is Err(InvalidOccurrence),
  )
  assert_true(
    prepare_source_state_requirement(identity, 0, 1, limits)
    is Err(InvalidOccurrence),
  )
  assert_true(
    prepare_source_state_requirement(identity, 0, 0, {
      ..limits,
      max_bytes: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "snapshot source selection does not fabricate a changes requirement" {
  let index = join_resolution_fixture()
  let identity = expression_closure_identity(
    operation_requirements_expressions(operation_resolution_requirements(index)),
  )
  assert_true(
    prepare_source_state_requirement(identity, 0, 0, {
      max_bytes: 0,
      max_nodes: 0,
      max_depth: 0,
    })
    is Ok(None),
  )
}
