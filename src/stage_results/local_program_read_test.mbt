///|
fn finish_original_local_program_read(
  read : LocalProgramRead,
) -> Result[(LocalProgramPreparation, LocalProgramUsage), LocalProgramIssue] raise {
  // Fixture transition bound only: Contract/Parameter continuations expose
  // separate constructor steps without increasing the semantic work Budget.
  // This is not a Program/Stage or language limit.
  for _ in 0..<200 {
    match local_program_read_phase(read) {
      Complete | Failed => return take_local_program_read(read).unwrap()
      _ => advance_local_program_read(read) |> ignore
    }
  }
  fail("original Local topology did not complete within fixture work")
}

///|
test "original staged topology retains Source Result producers and cumulative work across constructor returns" {
  for count in [1, 2] {
    let source = local_program_source(count == 2)
    let limits = local_program_limits()
    let read = begin_local_program_read(source, limits).unwrap()
    assert_true(take_local_program_read(read) is None)
    let mut spent = local_program_read_owned_work(read).unwrap()
    assert_eq(spent, count.to_int64())
    // Same fixture bound as the staged completion driver above.
    for _ in 0..<200 {
      if local_program_read_phase(read) == Complete {
        break
      }
      let phase = local_program_read_phase(read)
      let position = local_program_read_constructor_position(read)
      assert_eq(local_program_read_phase(read), phase)
      assert_eq(local_program_read_constructor_position(read), position)
      assert_eq(local_program_read_owned_work(read), Some(spent))
      assert_true(take_local_program_read(read) is None)
      advance_local_program_read(read) |> ignore
      if local_program_read_constructor_position(read) is Some((_, ordinal)) {
        assert_eq(ordinal, position.unwrap().1 + 1L)
      }
      let next = local_program_read_owned_work(read).unwrap()
      assert_true(next >= spent)
      spent = next
    }
    assert_eq(local_program_read_phase(read), Complete)
    assert_eq(advance_local_program_read(read), Complete)
    let completed = take_local_program_read(read).unwrap().unwrap()
    guard completed is (Publication(wiring), used) else {
      fail("expected original publication wiring")
    }
    assert_eq(spent, used.work.to_int64())
    assert_true(physical_equal(wiring_source(wiring), source))
    let (_, synchronous_usage) = prepare_local_program(source, limits).unwrap()
    assert_eq(used, synchronous_usage)
    assert_eq(export_count(wiring), 1)
    if count == 2 {
      let producer = wiring_stage_at(wiring, 0).unwrap()
      let imports = attached_imports(wiring_imports_at(wiring, 1).unwrap())
      assert_eq(import_count(imports), 2)
      for i in 0..<2 {
        assert_true(
          physical_equal(input_stage(import_at(imports, i).unwrap()), producer),
        )
      }
      assert_true(
        physical_equal(
          input_producer(import_at(imports, 0).unwrap()),
          input_producer(import_at(imports, 1).unwrap()),
        ),
      )
    }
    assert_true(take_local_program_read(read) is None)
    assert_eq(local_program_read_phase(read), Taken)
    clear_local_program_read(read)
    assert_true(physical_equal(wiring_source(wiring), source))
    assert_eq(advance_local_program_read(read), Taken)
  }
}

///|
test "original staged topology retains the exact later typed failure and never turns failed work into zero" {
  let source = local_program_source(true, bad_later=true)
  let limits = local_program_limits()
  let read = begin_local_program_read(source, limits).unwrap()
  for _ in 0..<100 {
    if local_program_read_phase(read) == Failed {
      break
    }
    assert_true(local_program_read_owned_work(read) is Some(_))
    advance_local_program_read(read) |> ignore
  }
  assert_eq(local_program_read_phase(read), Failed)
  assert_eq(
    local_program_read_constructor_position(read).map(p => p.0),
    Some(1),
  )
  assert_true(local_program_read_owned_work(read) is None)
  assert_eq(advance_local_program_read(read), Failed)
  guard take_local_program_read(read) is Some(Err(Pipeline(1, issue))) else {
    fail("expected original later Pipeline issue")
  }
  guard prepare_local_program(source, limits) is Err(Pipeline(1, prior)) else {
    fail("expected same synchronous typed issue")
  }
  assert_eq(issue.kind, prior.kind)
  assert_eq(issue.path, prior.path)
  assert_eq(
    @decode.tree_index(issue.source, prior.source),
    @decode.tree_index(issue.source, issue.source),
  )
  assert_true(take_local_program_read(read) is None)
}

///|
test "original staged topology preserves exact semantic limits and retires before an unexecuted Pipeline" {
  let source = local_program_source(true)
  let limits = local_program_limits()
  let (_, used) = prepare_local_program(source, limits).unwrap()
  let exact = {
    ..limits,
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_tokens: used.tokens,
    max_steps: used.steps,
    max_results: used.results,
    max_stages: 2,
  }
  let read = begin_local_program_read(source, exact).unwrap()
  guard finish_original_local_program_read(read) is Ok((Publication(_), actual)) else {
    fail("expected exact-budget topology")
  }
  assert_eq(actual, used)
  for
    short in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(prepare_local_program(source, short) is Err(_))
    let read = begin_local_program_read(source, short).unwrap()
    assert_true(finish_original_local_program_read(read) is Err(_))
  }
  assert_true(
    begin_local_program_read(source, { ..limits, max_work: -1, })
    is Err(InvalidLimits),
  )
  let read = begin_local_program_read(source, limits).unwrap()
  for _ in 0..<3 {
    advance_local_program_read(read) |> ignore
  }
  assert_eq(local_program_read_phase(read), Pipeline)
  clear_local_program_read(read)
  assert_eq(local_program_read_phase(read), Cleared)
  assert_eq(advance_local_program_read(read), Cleared)
  assert_true(local_program_read_owned_work(read) is None)
  assert_true(take_local_program_read(read) is None)
}

///|
test "original staged topology borrows admitted Local inputs without rebilling their prefix or replacing owners" {
  let source = local_program_source(true, untyped=true)
  let limits = local_program_limits()
  let environment = @local.prepare_environment(
    source,
    local_environment_fixture(),
    {
      max_work: limits.max_work,
      max_nodes: limits.max_nodes,
      max_text_bytes: limits.max_text_bytes,
      max_depth: limits.max_depth,
    },
  ).unwrap()
  let read = begin_local_program_read(
    source,
    limits,
    environment=Some(environment),
  ).unwrap()
  assert_eq(local_program_read_owned_work(read), Some(2L))
  let prefix = @local.program_environment_usage(environment).work
  assert_true(prefix > 0)
  for _ in 0..<100 {
    if local_program_read_phase(read) == Complete {
      break
    }
    advance_local_program_read(read) |> ignore
  }
  let owned = local_program_read_owned_work(read)
  guard finish_original_local_program_read(read)
    is Ok((Publication(wiring), used)) else {
    fail("expected original admitted environment")
  }
  assert_eq(owned, Some((used.work - prefix).to_int64()))
  assert_true(
    physical_equal(wiring_local_environment(wiring).unwrap(), environment),
  )
  assert_true(physical_equal(wiring_source(wiring), source))
  for i in 0..<2 {
    let attached = wiring_reconciled_input_at(wiring, i).unwrap()
    assert_true(
      physical_equal(
        @local.reconciled_inputs(attached),
        @local.program_environment_stage(environment, i).unwrap(),
      ),
    )
  }
  let (_, synchronous) = prepare_local_program(
    source,
    limits,
    environment=Some(environment),
  ).unwrap()
  assert_eq(used, synchronous)
  assert_true(
    begin_local_program_read(
      local_program_source(true, untyped=true),
      limits,
      environment=Some(environment),
    )
    is Err(ForeignEnvironmentSource),
  )
}

///|
test "zero Local inputs remain a real Values Stage while an empty Program keeps its original structural refusal" {
  assert_true(
    @syntax.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"empty\",\"stages\":[],\"results\":{}}",
      {
        source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
        tree: {
          max_nodes: 10000,
          max_depth: 100,
          max_string_bytes: 100000,
          max_total_string_bytes: 100000,
        },
        max_stages: 100,
      },
      format=Json,
    )
    is Err(@syntax.Structure(@syntax.EmptyStages, ..)),
  )
  let source = local_program_parse(
    "{\"version\":\"actql/0.1\",\"id\":\"zero-local\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"v\"}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[\"id\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
  )
  let read = begin_local_program_read(source, local_program_limits()).unwrap()
  guard finish_original_local_program_read(read)
    is Ok((Publication(wiring), used)) else {
    fail("expected real zero-Local-input Stage")
  }
  assert_eq(used.steps, 1)
  assert_eq(used.results, 1)
  assert_true(physical_equal(wiring_source(wiring), source))
  let stage = stage_port_source(wiring_stage_at(wiring, 0).unwrap())
  let pipeline = @collection.pipeline(@parameters.collection(stage))
  assert_eq(@pipeline.input_count(pipeline), 0)
  assert_eq(@schema.field_count(@pipeline.output_schema(pipeline).unwrap()), 1)
}
