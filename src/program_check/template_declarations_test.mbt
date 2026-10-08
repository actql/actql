///|
fn template_fixture(
  unused? : Bool = false,
  expression? : String = "id + $n",
) -> (
  @syntax.Program,
  @program_check.CheckEnvironment,
  @program_check.CheckLimits,
) {
  let (text, _, environment, _, limits) = public_input_fixture()
  let text = text.replace(old=",\"default\":1", new="")
  let text = if unused {
    text.replace(
      old="\"params\":{\"n\":{\"type\":\"number\"}}",
      new="\"params\":{\"n\":{\"type\":\"number\"},\"m\":{\"type\":\"number\"}}",
    )
  } else {
    text
  }
  let text = text.replace(old="id + $n", new=expression)
  let program = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="template.actql",
  ).unwrap()
  let limits = if unused {
    {
      ..limits,
      compilation: {
        ..limits.compilation,
        structure: { ..limits.compilation.structure, parameters: 2, },
      },
    }
  } else {
    limits
  }
  (program, environment, limits)
}

///|
test "template declaration preparation retains unbound whole Program reference and topology owners" {
  let (program, environment, limits) = template_fixture()
  assert_true(
    @program_check.check_parsed(program, environment, None, limits)
    is NeedsInputs(_),
  )
  let prepared = @program_check.prepare_template_declarations(
    program, environment, limits,
  ).unwrap()
  assert_true(
    physical_equal(
      @program_check.template_declarations_program(prepared),
      program,
    ),
  )
  assert_true(
    physical_equal(
      @program_check.template_declarations_environment(prepared),
      environment,
    ),
  )
  let wiring = @program_check.template_declarations_wiring(prepared)
  assert_true(
    physical_equal(@stages.program(@results.wiring_source(wiring)), program),
  )
  let usage = @program_check.template_declarations_usage(prepared)
  let source_preparation = @program_check.template_declarations_source(prepared)
  let topology = @context.sourceview_declaration_topology_usage(
    source_preparation,
  )
  // Existing topology owns registration and Local snapshot preparation already.
  // The only new join is gathering the retained stages before reference use.
  assert_eq(
    @context.sourceview_declaration_work(source_preparation),
    topology.work +
    @stages.stage_count(@results.wiring_source(wiring)) +
    @references.usage_work(usage),
  )
  let requests = @references.requests(@references.usage_inventory(usage))
  assert_true(
    physical_equal(@slots.source(requests), @results.wiring_source(wiring)),
  )
  assert_true(
    physical_equal(
      @local_inputs.program_environment(
        @results.wiring_local_environment(wiring).unwrap(),
      ),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let source = @results.stage_port_source(
    @results.wiring_stage_at(wiring, 0).unwrap(),
  )
  let declarations = @stages.declarations(@stages.source(source))
  assert_false(
    @parameters.has_default(
      @parameters.declaration_at(declarations, 0).unwrap(),
    ),
  )
  let (work, bytes, nodes) = @program_check.template_declarations_preparation_usage(
    prepared,
  )
  assert_true(work > @references.usage_work(usage))
  assert_true(bytes >= 0 && nodes >= 0)
  let exact = { ..limits, compilation: { ..limits.compilation, work, }, }
  assert_true(
    @program_check.prepare_template_declarations(program, environment, exact)
    is Ok(_),
  )
  assert_true(
    @program_check.prepare_template_declarations(program, environment, {
      ..exact,
      compilation: { ..exact.compilation, work: work - 1, },
    })
    is Err(_),
  )
  assert_true(
    @program_check.prepare_template_declarations(program, environment, {
      ..limits,
      compilation: { ..limits.compilation, work: 0, },
    })
    is Err(_),
  )
}

///|
test "template declaration preparation finds unused declarations without execution values" {
  let (program, environment, limits) = template_fixture(unused=true)
  assert_true(
    @program_check.check_parsed(program, environment, None, limits)
    is NeedsInputs(_),
  )
  guard @program_check.prepare_template_declarations(
      program, environment, limits,
    )
    is Err(Source(Identity(References(Usage(UnusedParameter(declaration)))))) else {
    fail("Expected the original unused declaration owner before value binding")
  }
  assert_eq(declaration.name, "m")
  assert_eq(@decode.cursor_path(@parameters.declaration_source(declaration)), [
    @source.Key("params"),
    @source.Key("m"),
  ])
  assert_eq(
    @decode.cursor_span(@parameters.declaration_source(declaration)).source_path,
    "template.actql",
  )
  assert_false(@parameters.has_default(declaration))
}

///|
test "template declaration preparation does not skip later invalid expressions behind missing values" {
  let (program, environment, limits) = template_fixture(
    expression="id + missing",
  )
  assert_true(
    @program_check.prepare_template_declarations(program, environment, limits)
    is Err(Source(SourceView(Program(Program(Pipeline(0, _)))))),
  )
  let (program, environment, limits) = template_fixture(expression="id + true")
  assert_true(
    @program_check.prepare_template_declarations(program, environment, limits)
    is Err(Source(SourceView(Program(Program(Pipeline(0, _)))))),
  )
}

///|
test "scoped template checking keeps partial preparation unresolved and rejects submitted bindings before checking" {
  let (program, environment, limits) = template_fixture()
  guard @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Unresolved(frontier)) else {
    fail("Declaration preparation cannot certify complete template scope")
  }
  assert_true(
    physical_equal(@program_check.template_frontier_program(frontier), program),
  )
  assert_true(
    physical_equal(
      @program_check.template_frontier_environment(frontier),
      environment,
    ),
  )
  assert_true(
    @program_check.template_frontier_declarations(frontier) is Some(_),
  )
  assert_true(@program_check.template_frontier_diagnostic(frontier) is None)
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
  let no_work = { ..limits, compilation: { ..limits.compilation, work: 0, }, }
  for supplied in ["{}", "null", "{\"n\":1}"] {
    assert_true(
      @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        Some(request_values(supplied)),
        no_work,
      )
      is InvalidRequest(BindingsInTemplateScope),
    )
  }
  guard @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      no_work,
    )
    is TemplateOnly(Unresolved(short)) else {
    fail("Budget exhaustion must retain the original template scope")
  }
  assert_true(@program_check.template_frontier_declarations(short) is None)
  assert_eq(
    @program_check.diagnostic_category(
      @program_check.template_frontier_diagnostic(short).unwrap(),
    ),
    CompileLimit,
  )
  let (program, environment, limits) = template_fixture(unused=true)
  guard @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Rejected(diagnostic)) else {
    fail("Unused declaration must be invalid even without its execution value")
  }
  assert_eq(@program_check.diagnostic_category(diagnostic), InvalidInput)
  assert_true(
    @program_check.diagnostic_cause(diagnostic)
    is Source(Identity(References(Usage(UnusedParameter(_))))),
  )
}

///|
test "scoped template declarations consume the actual SQL and AQL lowered Program without execution values" {
  let (_, _, environment, _, limits) = public_input_fixture()
  let declarations = @parameters.read_declarations(
    Some(request_values("{\"x\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let context = @frontend.bind_query_context(
    [],
    "template.fixture",
    parameter_declarations=Some(declarations),
  ).unwrap()
  let formats : Array[@frontend.Format] = [Sql, Text]
  for format in formats {
    let unused = @frontend.lower("SELECT 1 AS n", format, Some(context)).unwrap().program.unwrap()
    guard @program_check.check_parsed_scoped(
        unused,
        environment,
        TemplateOnly,
        None,
        limits,
      )
      is TemplateOnly(Rejected(diagnostic)) else {
      fail("The exact lowered Program must retain its unused x declaration")
    }
    assert_true(
      @program_check.diagnostic_cause(diagnostic)
      is Source(Identity(References(Usage(UnusedParameter(declaration))))) &&
      declaration.name == "x",
    )
    let used = @frontend.lower("SELECT @x AS n", format, Some(context)).unwrap().program.unwrap()
    guard @program_check.check_parsed_scoped(
        used,
        environment,
        TemplateOnly,
        None,
        limits,
      )
      is TemplateOnly(Unresolved(frontier)) else {
      fail(
        "Used x must retain prepared declarations, not claim complete static closure",
      )
    }
    assert_true(
      @program_check.template_frontier_declarations(frontier) is Some(_),
    )
    assert_true(
      physical_equal(@program_check.template_frontier_program(frontier), used),
    )
    assert_true(
      @program_check.check_parsed_scoped(
        used,
        environment,
        BoundInput,
        None,
        limits,
      )
      is BoundInput(NeedsInputs(_)),
    )
  }
}

///|
test "scoped template checking preserves unsupported authoring paths as unresolved" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let program = @syntax.parse(
    text.replace(
      old="\"params\":",
      new="\"bindings\":{\"b\":{\"type\":\"string\"}},\"params\":",
    ),
    limits.input,
    format=Json,
    source_path="unsupported.actql",
  ).unwrap()
  guard @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      None,
      limits,
    )
    is TemplateOnly(Unresolved(frontier)) else {
    fail(
      "Unsupported static paths cannot become author rejection or template success",
    )
  }
  assert_true(
    physical_equal(@program_check.template_frontier_program(frontier), program),
  )
  assert_true(@program_check.template_frontier_declarations(frontier) is None)
  let diagnostic = @program_check.template_frontier_diagnostic(frontier).unwrap()
  assert_eq(
    @program_check.diagnostic_category(diagnostic),
    UnsupportedImplementation,
  )
  assert_true(
    @program_check.diagnostic_cause(diagnostic)
    is Source(UnsupportedBindings(_)),
  )
}
