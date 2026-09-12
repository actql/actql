///|
fn local_context_limits() -> LocalContextLimits {
  {
    stages: {
      max_work: 10000000,
      max_text_bytes: 10000000,
      max_name_bytes: 1000000,
      max_input_work: 1000000,
      max_operand_work: 1000000,
    },
    max_policy_bytes: 10000,
    max_policy_nodes: 100,
    max_policy_depth: 10,
    max_local_input_nodes: 100000,
  }
}

///|
test "Local context preparation selects the retained Environment and shares every join budget" {
  let env = prepared_environment_fixture(capacity_profile(false))
  let prepared = prepared_local_source_fixture(
    environment=Some(env),
    third_stage=true,
  )
  let materials = capacity_materials_fixture(prepared).0
  let caps = local_context_limits()
  let checked = prepare_local_context(prepared, materials, caps).unwrap()
  assert_true(
    physical_equal(
      @environment.capacity_environment(selected_capacity(checked)),
      env,
    ),
  )
  let context = policy_context(checked)
  assert_true(
    physical_equal(
      result_wiring(reconciled_wiring(context)),
      @stage_results.local_source_wiring(prepared),
    ),
  )
  let stages = wired_stage_contexts(reconciled_wiring(context))
  assert_true(stage_context_at(stages, 2) is Some(_))
  assert_true(stage_context_at(stages, 3) is None)
  let used = selected_policy_usage(checked)
  let exact : LocalContextLimits = {
    ..caps,
    stages: {
      ..caps.stages,
      max_work: used.work,
      max_text_bytes: used.text_bytes,
    },
    max_policy_bytes: @environment.capacity_usage(selected_capacity(checked)).0,
    max_policy_nodes: used.policy_nodes,
    max_local_input_nodes: used.local_input_nodes,
  }
  assert_true(prepare_local_context(prepared, materials, exact) is Ok(_))
  assert_true(
    prepare_local_context(prepared, materials, {
      ..exact,
      stages: { ..exact.stages, max_work: used.work - 1, },
    })
    is Err(_),
  )
  assert_true(
    prepare_local_context(prepared, materials, {
      ..exact,
      stages: { ..exact.stages, max_text_bytes: used.text_bytes - 1, },
    })
    is Err(_),
  )
  assert_true(
    prepare_local_context(prepared, materials, {
      ..exact,
      max_policy_nodes: used.policy_nodes - 1,
    })
    is Err(_),
  )
  assert_true(
    prepare_local_context(prepared, materials, {
      ..exact,
      max_policy_bytes: exact.max_policy_bytes - 1,
    })
    is Err(Policy(BudgetExceeded)),
  )
  assert_true(
    prepare_local_context(prepared, materials, {
      ..exact,
      max_policy_depth: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "Local context preparation does not invent an Environment or a capacity component" {
  let bare = prepared_local_source_fixture()
  assert_true(
    prepare_local_context(
      bare,
      capacity_materials_fixture(bare).0,
      local_context_limits(),
    )
    is Err(MissingEnvironment),
  )
  let env = prepared_environment_fixture("{}")
  let prepared = prepared_local_source_fixture(environment=Some(env))
  assert_true(
    prepare_local_context(
      prepared,
      capacity_materials_fixture(prepared).0,
      local_context_limits(),
    )
    is Err(Policy(MissingCapacity)),
  )
}
