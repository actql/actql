///|
fn local_program_context_source(text : String) -> @syntax.Program {
  @syntax.parse(
    text,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 3,
    },
    format=Json,
  ).unwrap()
}

///|
fn local_program_context_source_limits() -> @stage_results.LocalProgramLimits {
  {
    max_stages: 3,
    max_steps: 10,
    max_results: 10,
    max_work: 1000000,
    max_nodes: 100000,
    max_tokens: 10000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }
}

///|
test "parsed Local Program connects three Stage imports and rejects a late invalid consumer" {
  let program = local_source_program_fixture(third_stage=true)
  let env = prepared_environment_fixture(capacity_profile(false))
  let materials : Array[Array[CapacityMaterial]] = []
  // The second Stage imports the first Result twice; those visits retain
  // separate ownership. The third Stage also visits that complete chain.
  for count in [1, 3, 4] {
    materials.push(
      Array::makei(count, _ => {
        sources: empty_capacity_sources(),
        consumers: [],
      }),
    )
  }
  let caps = local_context_limits()
  let source_caps = local_program_context_source_limits()
  let selected = prepare_local_program_context(
    program,
    None,
    env,
    materials,
    source_caps,
    caps,
    max_parameters=1,
  ).unwrap()
  let identity = prepared_selected_identity(selected, max_stages=3)
  assert_eq(program_identity_stage_count(identity), 3)
  for stage in 0..<3 {
    assert_eq(
      program_identity_producer_count(identity, stage),
      Some([1, 3, 4][stage]),
    )
  }
  materials[2][2] = {
    sources: empty_capacity_sources(),
    consumers: [@capacity.Join(step=0, output=0)],
  }
  assert_true(
    prepare_local_program_context(
      program,
      None,
      env,
      materials,
      source_caps,
      caps,
      max_parameters=1,
    )
    is Err(Context(Stages(Capacity(2, 2, _)))),
  )
  // Rejected later preparation cannot mutate the already-owned successful result.
  assert_eq(program_identity_stage_count(identity), 3)
}

///|
test "parsed Local Program reaches owned identity preparation without caller-created checks" {
  let text =
    #|{"version":"actql/0.1","id":"local-entry","params":{"n":{"type":"number","default":2}},"stages":[{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}}],"results":{"out":{"from":{"stage":"first","result":"out"}}}}
  let program = local_program_context_source(text)
  let env = prepared_environment_fixture(capacity_profile(false))
  // This single scalar pipeline has no acquired sources or capacity claims.
  // The material is explicit and does not default missing claims for other ops.
  let materials = [
    [CapacityMaterial::{ sources: empty_capacity_sources(), consumers: [], }],
  ]
  let caps = local_context_limits()
  let source_caps = local_program_context_source_limits()
  let selected = prepare_local_program_context(
    program,
    None,
    env,
    materials,
    source_caps,
    caps,
    max_parameters=1,
  ).unwrap()
  let wiring = result_wiring(reconciled_wiring(policy_context(selected)))
  assert_true(
    physical_equal(
      @stages.program(@stage_results.wiring_source(wiring)),
      program,
    ),
  )
  let identity = prepared_selected_identity(selected, max_stages=1)
  assert_eq(program_identity_stage_count(identity), 1)
  let used = selected_policy_usage(selected)
  let exact = {
    ..caps,
    stages: {
      ..caps.stages,
      max_work: used.work,
      max_text_bytes: used.text_bytes,
    },
  }
  assert_true(
    prepare_local_program_context(
      program,
      None,
      env,
      materials,
      source_caps,
      exact,
      max_parameters=1,
    )
    is Ok(_),
  )
  for
    short in [
      { ..exact, stages: { ..exact.stages, max_work: used.work - 1, }, },
      {
        ..exact,
        stages: { ..exact.stages, max_text_bytes: used.text_bytes - 1, },
      },
    ] {
    assert_true(
      prepare_local_program_context(
        program,
        None,
        env,
        materials,
        source_caps,
        short,
        max_parameters=1,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_local_program_context(
      program,
      None,
      env,
      [],
      source_caps,
      caps,
      max_parameters=1,
    )
    is Err(Context(Stages(StageCount))),
  )
  let missing = local_program_context_source(
    text.replace(old=",\"default\":2", new=""),
  )
  assert_true(
    prepare_local_program_context(
      missing,
      None,
      env,
      materials,
      source_caps,
      caps,
      max_parameters=1,
    )
    is Err(Source(NeedsBindings(_))),
  )
  let bad = local_program_context_source(
    text.replace(old="id + $n", new="missing + $n"),
  )
  assert_true(
    prepare_local_program_context(
      bad,
      None,
      env,
      materials,
      source_caps,
      caps,
      max_parameters=1,
    )
    is Err(Source(Program(Pipeline(0, _)))),
  )
}
