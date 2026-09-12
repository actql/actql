///|
test "Local environment preparation admits and partitions every snapshot from its owner" {
  let source = two_stage_source()
  // Environment order is deliberately different from source Stage order.
  let (environment, _) = environment_for([
    snapshot_in_stage("t", "b", schema_fields()),
    snapshot_in_stage("s", "b", schema_fields()),
  ])
  let prepared = prepare_environment(source, environment, caps()).unwrap()
  assert_true(physical_equal(environment_program(prepared), source))
  assert_true(physical_equal(program_environment(prepared), environment))
  for (i, name) in [(0, "s"), (1, "t")] {
    let stage = program_environment_stage(prepared, i).unwrap()
    assert_true(physical_equal(input_environment(stage), environment))
    assert_eq(snapshot_count(environment_assertions(stage)), 1)
    let admitted = environment_snapshot_at(stage, 0).unwrap()
    assert_eq(
      @source_ref.stage_name(
        @snapshot.source_reference(@snapshot.environment_snapshot(admitted)),
      ),
      name,
    )
    assert_true(environment_input_at(stage, 0) is Some(_))
  }
  let used = program_environment_usage(prepared)
  let exact : Limits = {
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_depth: 100,
  }
  assert_true(prepare_environment(source, environment, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(prepare_environment(source, environment, short) is Err(_))
  }
  assert_true(
    prepare_environment(source, environment, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "Local environment preparation rejects unknown snapshot targets and late-stage failure" {
  let source = two_stage_source()
  let (unknown, _) = environment_for([
    snapshot_in_stage("missing", "b", schema_fields()),
  ])
  assert_true(
    prepare_environment(source, unknown, caps())
    is Err(UnknownStage(_, "missing")),
  )
  let (later, _) = environment_for([
    snapshot_in_stage("s", "b", schema_fields()),
    snapshot_in_stage("t", "missing", schema_fields()),
  ])
  assert_true(
    prepare_environment(source, later, caps()) is Err(Environment(1, _)),
  )
  let (empty, _) = environment_for([])
  let result = prepare_environment(source, empty, caps()).unwrap()
  for i in 0..<2 {
    assert_eq(
      snapshot_count(
        environment_assertions(program_environment_stage(result, i).unwrap()),
      ),
      0,
    )
  }
}

///|
test "environment preparation retains owned SourceView partitions without treating them as Local snapshots" {
  let wire = "{\"connector\":\"crm\",\"resource\":\"rows\"}"
  let source = mixed_source(wire)
  let views = @sourceviews.collect(source, {
    max_work: 10000,
    max_order_keys: 10,
  }).unwrap()
  let (environment, _) = environment_for([
    snapshot_in_stage("s", "rows", schema_fields()),
    snapshot_in_stage("t", "remote", schema_fields()),
  ])
  assert_true(
    prepare_environment(source, environment, caps())
    is Err(Stage(0, Declaration("remote", _))),
  )
  let prepared = prepare_environment(
    source,
    environment,
    caps(),
    sourceviews=Some(views),
  ).unwrap()
  for (stage, name) in [(0, "rows"), (1, "remote")] {
    let admitted = program_environment_stage(prepared, stage).unwrap()
    let partition = snapshot_inputs(environment_assertions(admitted))
    assert_true(physical_equal(sourceview_inputs(partition).unwrap(), views))
    assert_eq(count(partition), 1)
    assert_eq(entry_at(partition, 0).unwrap().0, name)
    assert_eq(snapshot_count(environment_assertions(admitted)), 1)
  }
  let used = program_environment_usage(prepared)
  let exact : Limits = {
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_depth: 100,
  }
  assert_true(
    prepare_environment(source, environment, exact, sourceviews=Some(views))
    is Ok(_),
  )
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      prepare_environment(source, environment, short, sourceviews=Some(views))
      is Err(_),
    )
  }
  assert_true(
    prepare_environment(
      mixed_source(wire),
      environment,
      caps(),
      sourceviews=Some(views),
    )
    is Err(ForeignSourceViews),
  )
  let (invalid, _) = environment_for([
    snapshot_in_stage("s", "remote", schema_fields()),
  ])
  assert_true(
    prepare_environment(source, invalid, caps(), sourceviews=Some(views))
    is Err(Environment(0, _)),
  )
}
