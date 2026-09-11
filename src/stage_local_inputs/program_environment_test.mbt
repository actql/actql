///|
fn two_stage_source() -> @stages.Source {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{"b":"relation"},"steps":[],"results":{"out":{}}},{"id":"t","inputs":{"b":"relation","r":{"result":{"stage":"s","result":"out"}}},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"t","result":"out"}}}}
    ),
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
fn assemble_fixture(
  source : @stages.Source,
) -> (@environment.WireEnvironment, Array[EnvironmentInputs]) raise @encode.EncodeFailure {
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let (environment, members) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "b", schema_fields()),
  ])
  let by_stage : Array[Array[@snapshot.EnvironmentSnapshot]] = [[], []]
  for entry in members {
    let stage = @source_ref.stage_name(
      @snapshot.source_reference(@snapshot.environment_snapshot(entry)),
    )
    by_stage[if stage == "s" { 0 } else { 1 }].push(entry)
  }
  let checked = []
  for i in 0..<2 {
    checked.push(
      reconcile_environment(
        prepare(source, i, caps()).unwrap(),
        index,
        environment,
        by_stage[i],
        caps(),
      ).unwrap(),
    )
  }
  (environment, checked)
}

///|
test "all-stage environment assembly covers snapshots and indexes source order" {
  let source = two_stage_source()
  let (environment, stages) = assemble_fixture(source)
  let supplied = [stages[1], stages[0]]
  let result = assemble_environment(source, environment, supplied, caps()).unwrap()
  supplied.clear()
  assert_true(physical_equal(environment_program(result), source))
  assert_true(physical_equal(program_environment(result), environment))
  for i in 0..<2 {
    assert_true(
      physical_equal(program_environment_stage(result, i).unwrap(), stages[i]),
    )
  }
  assert_true(program_environment_stage(result, -1) is None)
  assert_true(program_environment_stage(result, 2) is None)
  let used = program_environment_usage(result)
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(assemble_environment(source, environment, stages, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      assemble_environment(source, environment, stages, limit)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    assemble_environment(source, environment, stages, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "assembly rejects foreign owners repeated stages and omitted supplied evidence" {
  let source = two_stage_source()
  let (environment, stages) = assemble_fixture(source)
  assert_true(
    assemble_environment(source, environment, [stages[0]], caps())
    is Err(StageCountMismatch),
  )
  assert_true(
    assemble_environment(source, environment, [stages[0], stages[0]], caps())
    is Err(DuplicateStage(0)),
  )
  let (other_env, other_stages) = assemble_fixture(source)
  assert_eq(@environment.cid(other_env), @environment.cid(environment))
  assert_true(
    assemble_environment(
      source,
      environment,
      [stages[0], other_stages[1]],
      caps(),
    )
    is Err(ForeignEnvironment(1)),
  )
  assert_true(
    assemble_environment(two_stage_source(), environment, stages, caps())
    is Err(ForeignProgram(0)),
  )
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let empty = reconcile_environment(
    prepare(source, 1, caps()).unwrap(),
    index,
    environment,
    [],
    caps(),
  ).unwrap()
  assert_true(
    assemble_environment(source, environment, [stages[0], empty], caps())
    is Err(UncheckedSnapshot(_)),
  )
  let (no_evidence, _) = environment_for([])
  let no_members = [0, 1].map(i => {
    reconcile_environment(
      prepare(source, i, caps()).unwrap(),
      index,
      no_evidence,
      [],
      caps(),
    ).unwrap()
  })
  // No supplied schema is not the same as a missing supplied member; the later
  // compiler still decides which inputs require additional evidence.
  assert_true(
    assemble_environment(source, no_evidence, no_members, caps()) is Ok(_),
  )
}
