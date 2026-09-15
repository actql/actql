///|
test "authored capacity inputs expand across repeated imports without caller visits" {
  let prepared = prepared_local_source_fixture(third_stage=true)
  let program = @stages.program(@stage_results.local_source_source(prepared))
  let inputs = bind_capacity_inputs(program, [], 1000).unwrap()
  // Three Stage names: first, second, third. Copy, retained slot and name work,
  // plus the fixed empty-inventory construction; no contextual visits supplied.
  assert_eq(capacity_inputs_work(inputs), 4 + 2 * 3 + 6 + 7 + 6)
  assert_true(bind_capacity_inputs(program, [], 29) is Ok(_))
  assert_true(bind_capacity_inputs(program, [], 28) is Err(BudgetExceeded))
  let caps = local_context_limits().stages
  let direct = prepare_local_stage_contexts(
    prepared,
    capacity_materials_fixture(prepared).0,
    policy(),
    caps,
  ).unwrap()
  let selected = prepare_local_stage_contexts_from_inputs(
    prepared,
    inputs,
    policy(),
    caps,
  ).unwrap()
  // Actual closure visits are 1 + 3 + 4. Two passes over the three Stage roots,
  // one retained reference and one exact owner comparison per visit.
  let expansion = 1 + 2 * 3 + 2 * 8
  assert_eq(stage_usage(selected).0, stage_usage(direct).0 + expansion)
  assert_true(
    physical_equal(stage_operations(selected), stage_operations(direct)),
  )
  let exact = { ..caps, max_work: stage_usage(direct).0 + expansion, }
  assert_true(
    prepare_local_stage_contexts_from_inputs(prepared, inputs, policy(), exact)
    is Ok(_),
  )
  assert_true(
    prepare_local_stage_contexts_from_inputs(prepared, inputs, policy(), {
      ..exact,
      max_work: exact.max_work - 1,
    })
    is Err(_),
  )
  let other = prepared_local_source_fixture(third_stage=true)
  assert_true(
    prepare_local_stage_contexts_from_inputs(other, inputs, policy(), caps)
    is Err(Inputs(ForeignProgram)),
  )
  assert_true(
    prepare_local_stage_contexts_from_inputs(prepared, inputs, policy(), {
      ..caps,
      max_text_bytes: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "capacity input binding rejects unknown and duplicate authored selectors" {
  let program = local_source_program_fixture()
  let sources = empty_capacity_sources()
  let entries : Array[StageCapacityInput] = [
    { stage: "first", sources, uses: [], },
  ]
  assert_true(bind_capacity_inputs(program, entries, 1000) is Ok(_))
  assert_true(
    bind_capacity_inputs(program, [entries[0], entries[0]], 1000)
    is Err(DuplicateStage(1)),
  )
  assert_true(
    bind_capacity_inputs(
      program,
      [{ stage: "missing", sources, uses: [], }],
      1000,
    )
    is Err(UnknownStage(0)),
  )
  assert_true(bind_capacity_inputs(program, [], -1) is Err(InvalidLimits))
  assert_true(bind_capacity_inputs(program, [], 0) is Err(BudgetExceeded))
}
