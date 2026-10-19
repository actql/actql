///|
fn complete_template_fixture(
  suffix? : String = "",
  default_value? : String = "",
  expression? : String = "id + $x",
  value_cell? : Bool = false,
) -> (
  @syntax.Program,
  @program_check.CheckEnvironment,
  @program_check.CheckLimits,
) {
  let (_, _, environment, _, limits) = public_input_fixture()
  let text =
    #|{"version":"actql/0.1","id":"authoring","params":{"x":{"type":"number"DEFAULT}},"stages":[{"id":"first","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":CELL}]},"as":"seed"},{"derive":{"n":"EXPRESSION"}},{"select":["n"],"as":"output"}SUFFIX],"results":{"out":{"from":"output","fields":["n"]}}}],"results":{"out":{"from":{"stage":"first","result":"out"}}}}
  let text = text
    .replace(old="DEFAULT", new=default_value)
    .replace(
      old="CELL",
      new=if value_cell { "{\"$param\":\"x\"}" } else { "1" },
    )
    .replace(old="EXPRESSION", new=expression)
    .replace(old="SUFFIX", new=suffix)
  (@syntax.parse(text, limits.input, format=Json).unwrap(), environment, limits)
}

///|
test "complete template closure retains the original Program and all static owners without bound values" {
  let (program, environment, limits) = complete_template_fixture()
  let prepared = @program_check.prepare_template_declarations(
    program, environment, limits,
  ).unwrap()
  let checked = @program_check.complete_template_check(prepared).unwrap()
  assert_true(
    physical_equal(@program_check.template_checked_program(checked), program),
  )
  assert_true(
    physical_equal(
      @program_check.template_checked_environment(checked),
      environment,
    ),
  )
  assert_true(
    physical_equal(
      @program_check.template_checked_declarations(checked),
      prepared,
    ),
  )
  let contracts = @program_check.template_checked_contracts(checked)
  assert_true(
    physical_equal(
      @context.authoring_core_contract_source(contracts),
      @program_check.template_declarations_source(prepared),
    ),
  )
  assert_true(
    physical_equal(
      @references.program_definition_semantics(
        @program_check.template_checked_definition(checked),
      ),
      @context.authoring_core_contract_semantics(contracts),
    ),
  )
  assert_true(
    physical_equal(
      @environment.capacity_environment(
        @program_check.template_checked_capacity(checked),
      ),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let publication = @context.authoring_core_contract_publication_at(
    contracts, 0,
  ).unwrap()
  let stage = @results.wiring_stage_at(
    @program_check.template_declarations_wiring(prepared),
    0,
  ).unwrap()
  assert_true(
    physical_equal(
      @context.authoring_publication_ports(publication),
      @results.stage_port_publications(stage),
    ),
  )
  assert_true(
    @context.authoring_core_contract_publication_at(contracts, 1) is None,
  )
  assert_eq(@program_check.template_checked_input_count(checked), 1)
  let request = @program_check.template_checked_input_at(checked, 0).unwrap()
  assert_true(
    request.kind is ParameterValue(declaration) &&
    declaration.name == "x" &&
    !@parameters.has_default(declaration),
  )
  assert_true(physical_equal(request.program, program))
  assert_true(physical_equal(request.environment, environment))
  assert_eq(@program_check.input_request_path(request), [
    Key("params"),
    Key("x"),
  ])
  assert_true(@program_check.input_request_source(request) is Some(_))
  assert_true(@program_check.template_checked_input_at(checked, -1) is None)
  assert_true(@program_check.template_checked_input_at(checked, 1) is None)
  assert_true(
    @program_check.check_parsed_scoped(
      program,
      environment,
      BoundInput,
      None,
      limits,
    )
    is BoundInput(NeedsInputs(_)),
  )
}

///|
test "complete template closure replays its cumulative work and refuses each exhausted budget" {
  let (program, environment, limits) = complete_template_fixture()
  let checked = @program_check.complete_template_check(
    @program_check.prepare_template_declarations(program, environment, limits).unwrap(),
  ).unwrap()
  let (work, bytes, nodes) = @program_check.template_checked_usage(checked)
  assert_true(work > 0 && bytes > 0 && nodes > 0)
  let prepared = @program_check.prepare_template_declarations(
    program, environment, limits,
  ).unwrap()
  let (declaration_work, _, _) = @program_check.template_declarations_preparation_usage(
    prepared,
  )
  assert_true(work > declaration_work)
  let partial_limits = {
    ..limits,
    compilation: { ..limits.compilation, work: declaration_work, },
  }
  // Successful preparation under its own exact cap cannot borrow a previously
  // prepared larger allowance or be completed under caller-supplied credits.
  let partial = @program_check.prepare_template_declarations(
    program, environment, partial_limits,
  ).unwrap()
  assert_true(
    @program_check.complete_template_check(partial) is Err(BudgetExceeded),
  )
  let exact = {
    ..limits,
    compilation: {
      ..limits.compilation,
      work,
      artifacts: { ..limits.compilation.artifacts, bytes, nodes, },
    },
  }
  assert_true(
    @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      exact,
    )
    is TemplateOnly(Verified(_)),
  )
  for
    limited in [
      { ..exact, compilation: { ..exact.compilation, work: work - 1, }, },
      {
        ..exact,
        compilation: {
          ..exact.compilation,
          artifacts: { ..exact.compilation.artifacts, bytes: bytes - 1, },
        },
      },
      {
        ..exact,
        compilation: {
          ..exact.compilation,
          artifacts: { ..exact.compilation.artifacts, nodes: nodes - 1, },
        },
      },
      {
        ..exact,
        compilation: {
          ..exact.compilation,
          structure: { ..exact.compilation.structure, requirements: 0, },
        },
      },
    ] {
    guard @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        None,
        limited,
      )
      is TemplateOnly(Unresolved(frontier)) else {
      fail("No exhausted original scope may become verified or author-invalid")
    }
    let diagnostic = @program_check.template_frontier_diagnostic(frontier).unwrap()
    assert_eq(@program_check.diagnostic_category(diagnostic), CompileLimit)
    assert_true(
      physical_equal(
        @program_check.template_frontier_program(frontier),
        program,
      ),
    )
  }
}

///|
test "complete template closure uses admitted defaults and refuses unsupported static and missing resource material" {
  let (program, environment, limits) = complete_template_fixture(
    default_value=",\"default\":1",
  )
  guard @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Verified(checked)) else {
    fail("An admitted default is not an invented placeholder")
  }
  assert_eq(@program_check.template_checked_input_count(checked), 0)
  let (program, environment, limits) = complete_template_fixture(
    default_value=",\"default\":null",
  )
  assert_true(
    @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Rejected(_)),
  )
  for unsupported in [",{\"distinct\":true}", ",{\"take\":{\"$param\":\"x\"}}"] {
    let (program, environment, limits) = complete_template_fixture(
      suffix=unsupported,
    )
    guard @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        None,
        limits,
      )
      is TemplateOnly(Unresolved(frontier)) else {
      fail("Unconnected operations must retain the complete original scope")
    }
    assert_eq(
      @program_check.diagnostic_category(
        @program_check.template_frontier_diagnostic(frontier).unwrap(),
      ),
      UnsupportedImplementation,
    )
  }
  let (program, environment, limits) = complete_template_fixture(
    expression="regex_match(NULL, 'a') + $x",
  )
  // Static expression admission rejects this independent type error before
  // missing execution values; it cannot be a successful prepared remainder.
  assert_true(
    @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Rejected(_)),
  )
  let (program, environment, limits) = complete_template_fixture(
    value_cell=true,
  )
  guard @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Unresolved(frontier)) else {
    fail("Unmeasurable Values payloads cannot become runtime-only success")
  }
  assert_eq(
    @program_check.diagnostic_category(
      @program_check.template_frontier_diagnostic(frontier).unwrap(),
    ),
    MissingInput,
  )
}

///|
test "complete template closure verifies actual parameter-free SQL and AQL without execution requirements" {
  let (_, _, environment, _, limits) = public_input_fixture()
  let context = @frontend.bind_query_context([], "literal-template.fixture").unwrap()
  let formats : Array[@frontend.Format] = [Sql, Text]
  for format in formats {
    let program = @frontend.lower("SELECT 1 AS n", format, Some(context)).unwrap().program.unwrap()
    guard @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        None,
        limits,
      )
      is TemplateOnly(Verified(checked)) else {
      fail("The entire lowered literal template must close without execution")
    }
    assert_eq(@program_check.template_checked_input_count(checked), 0)
    assert_true(
      physical_equal(@program_check.template_checked_program(checked), program),
    )
    assert_true(
      @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        Some(request_values("{}")),
        limits,
      )
      is InvalidRequest(BindingsInTemplateScope),
    )
  }
}

///|
test "complete template closure retains original Sort and literal Take orders" {
  for
    suffix in [
      ",{\"sort\":[{\"n\":\"desc\"}],\"as\":\"ordered\"}", ",{\"take\":1,\"as\":\"ordered\"}",
      ",{\"sort\":[{\"n\":\"desc\"}]},{\"take\":{\"count\":1,\"offset\":0},\"as\":\"ordered\"}",
    ] {
    let (program, environment, limits) = complete_template_fixture(suffix~)
    let result = @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    guard result is TemplateOnly(Verified(checked)) else {
      fail(
        "original ordered template must close through the existing order owner",
      )
    }
    assert_true(
      physical_equal(@program_check.template_checked_program(checked), program),
    )
    assert_eq(@program_check.template_checked_input_count(checked), 1)
    assert_true(
      @program_check.template_checked_input_at(checked, 0).unwrap().kind
      is ParameterValue(_),
    )
  }
}
