///|
test "source identity orchestration preserves existing identities and exact aggregate limits" {
  let (identity, _, _) = prepared_identity_fixture()
  let operations = program_sources_operations(
    program_identity_sources(identity),
  )
  let original = source_preparation_limits()
  let (work, bytes, nodes) = program_identity_usage(identity)
  let limits : SourcePreparationLimits = {
    ..original,
    identity: {
      ..original.identity,
      max_work: work,
      max_stages: 2,
      max_hash_bytes: bytes,
      max_hash_nodes: nodes,
    },
  }
  let result = prepare_program_source_identity(operations, limits).unwrap()
  assert_eq(program_identity_usage(result), (work, bytes, nodes))
  assert_eq(
    program_identity_definition_cid(result),
    program_identity_definition_cid(identity),
  )
  assert_eq(
    program_identity_parameter_values_cid(result),
    program_identity_parameter_values_cid(identity),
  )
  assert_true(
    physical_equal(
      program_sources_operations(program_identity_sources(result)),
      operations,
    ),
  )
  assert_false(physical_equal(result, identity))
  for
    cap in [
      { ..limits.identity, max_work: work - 1, },
      { ..limits.identity, max_stages: 1, },
      { ..limits.identity, max_hash_bytes: bytes - 1, },
      { ..limits.identity, max_hash_nodes: nodes - 1, },
      { ..limits.identity, max_depth: 0, },
    ] {
    assert_true(
      prepare_program_source_identity(operations, { ..limits, identity: cap, })
      is Err(_),
    )
  }
  assert_true(
    prepare_program_source_identity(operations, { ..limits, max_bindings: -1, })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_program_source_identity(operations, {
      ..limits,
      identity: { ..limits.identity, max_work: -1, },
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_program_source_identity(operations, {
      ..limits,
      identity: { ..limits.identity, max_work: 0, },
    })
    is Err(BudgetExceeded),
  )
  // Independent composition uses the same original owners, not the new result.
  let references = prepared_reference_branch(operations, 10000000).unwrap()
  let preparation = operation_profiles_preparation(operations)
  let bindings = collect_source_bindings(preparation, 10000000, 100).unwrap()
  let sources = bind_program_sources(operations, references, bindings, 10000000).unwrap()
  let baseline = identify_program_sources(sources, original.identity).unwrap()
  assert_eq(program_identity_usage(baseline), program_identity_usage(result))
  assert_eq(
    program_identity_definition_cid(baseline),
    program_identity_definition_cid(result),
  )
}
