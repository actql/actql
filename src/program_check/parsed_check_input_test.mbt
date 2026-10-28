///|
test "parsed check input retains original owners and bound evidence across caller registration mutation" {
  let (_, program, environment, evidence, limits) = public_input_fixture(
    generated=true,
    repeated=true,
  )
  let original_sources = evidence[0].sources
  let prepared = @program_check.prepare_parsed_check_input(
    program,
    environment,
    None,
    evidence,
    limits,
  ).unwrap()
  assert_true(physical_equal(prepared.program, program))
  assert_true(physical_equal(prepared.environment, environment))
  let work = @program_check.parsed_check_input_binding_work(prepared)
  assert_true(work > 0 && work < limits.compilation.work)
  // A second binding of these late registrations must refuse. The retained
  // input instead uses the original binder's owned materials and consumers.
  evidence.clear()
  evidence.push({
    stage: "not-an-original-stage",
    sources: original_sources,
    uses: [],
  })
  assert_true(
    @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      limits,
    )
    is Err(CapacityInputs(UnknownStage(0))),
  )
  let checked = public_checked(
    @program_check.finish_parsed_check_input(prepared),
  )
  assert_eq(@program_check.unit_count(checked), 2)
  assert_eq(
    @context.program_identity_stage_count(
      @program_check.source_identity(checked),
    ),
    2,
  )
  assert_eq(@program_check.parsed_check_input_binding_work(prepared), work)
  let imported = @program_check.unit_result_import_at(checked, 1, 0).unwrap()
  assert_eq(imported.producer_node_id, "producer")
  assert_eq(imported.result_name, "out")
  assert_eq(imported.input_name, "rows")
}

///|
test "parsed check preparation keeps invalid limit precedence and exact original binding work bound" {
  let (_, program, environment, evidence, limits) = public_input_fixture(
    generated=true,
  )
  assert_true(
    @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      {
        input: { ..limits.input, max_stages: 1, },
        compilation: { ..limits.compilation, work: -1, },
      },
    )
    is Err(InvalidLimits),
  )
  assert_true(
    @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      { ..limits, input: { ..limits.input, max_stages: 1, }, },
    )
    is Err(Program(RetentionLimit(Stages, ..))),
  )
  let prepared = @program_check.prepare_parsed_check_input(
    program,
    environment,
    None,
    evidence,
    limits,
  ).unwrap()
  let used = @program_check.parsed_check_input_binding_work(prepared)
  assert_true(
    @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      { ..limits, compilation: { ..limits.compilation, work: used - 1, }, },
    )
    is Err(CapacityInputs(BudgetExceeded)),
  )
  let exact = @program_check.prepare_parsed_check_input(
    program,
    environment,
    None,
    evidence,
    { ..limits, compilation: { ..limits.compilation, work: used, }, },
  ).unwrap()
  assert_eq(@program_check.parsed_check_input_binding_work(exact), used)
  // Prefix readiness is not a successful complete check under zero remaining
  // semantic work. Its actual typed continuation still refuses.
  assert_true(@program_check.finish_parsed_check_input(exact) is Rejected(_))
}

///|
test "parsed check input retains exact Catalog owner and original missing Parameter requests" {
  let (text, program, environment, _, limits) = public_input_fixture()
  let catalog = @program_check.prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let (_, _, foreign, _, _) = public_input_fixture()
  assert_eq(
    @program_check.checking_environment_cid(foreign),
    @program_check.checking_environment_cid(environment),
  )
  assert_true(
    @program_check.prepare_parsed_check_input(
      program,
      foreign,
      None,
      [],
      limits,
      source_catalog=Some(catalog),
    )
    is Err(Environment(ForeignPreparedCatalog)),
  )
  let original = @syntax.parse(
    text.replace(old=",\"default\":1", new=""),
    limits.input,
    format=Json,
    source_path="retained-check.actql",
  ).unwrap()
  let prepared = @program_check.prepare_parsed_check_input(
    original,
    environment,
    None,
    [],
    limits,
    source_catalog=Some(catalog),
  ).unwrap()
  guard @program_check.finish_parsed_check_input(prepared)
    is NeedsInputs(requests) else {
    fail("original missing Parameter frontier was lost")
  }
  assert_eq(@program_check.input_request_count(requests), 1)
  let request = @program_check.input_request_at(requests, 0).unwrap()
  assert_true(physical_equal(request.program, original))
  assert_true(physical_equal(request.environment, environment))
  guard request.kind is ParameterValue(declaration) else {
    fail("expected original typed Parameter request")
  }
  assert_eq(declaration.name, "n")
  assert_false(@parameters.has_default(declaration))
  let source = @parameters.declaration_source(declaration)
  assert_eq(@decode.cursor_span(source).source_path, "retained-check.actql")
}
