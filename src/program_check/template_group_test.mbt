///|
fn group_template_fixture(
  call : String,
  parameters? : String = "{}",
) -> (
  @syntax.Program,
  @program_check.CheckEnvironment,
  @program_check.CheckLimits,
) {
  let (_, environment, limits) = complete_template_fixture()
  let declarations = if parameters == "{}" {
    ""
  } else {
    ",\"params\":" + parameters
  }
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"group-template\"" +
    declarations +
    ",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":1}]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"total\":" +
    call +
    "}},\"as\":\"output\"}],\"results\":{\"out\":{\"from\":\"output\",\"fields\":[\"total\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"main\",\"result\":\"out\"}}}}"
  (@syntax.parse(wire, limits.input, format=Json).unwrap(), environment, limits)
}

///|
test "complete Group templates retain original Program and missing bindings" {
  for
    (call, parameters, missing) in [
      ("{\"fn\":\"count\"}", "{}", 0),
      ("{\"fn\":\"min\",\"field\":\"n\"}", "{}", 0),
      ("{\"fn\":\"max\",\"field\":\"n\"}", "{}", 0),
      ("{\"fn\":\"count\",\"expr\":\"$x\"}", "{\"x\":{\"type\":\"number\"}}", 1),
    ] {
    let (program, environment, limits) = group_template_fixture(
      call,
      parameters~,
    )
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
    assert_eq(@program_check.template_checked_input_count(checked), missing)
    assert_eq(@program_check.template_checked_condition_count(checked), 0)
    assert_true(
      @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        None,
        limits,
      )
      is TemplateOnly(Verified(_)),
    )
    let (work, _, _) = @program_check.template_checked_usage(checked)
    let exhausted = {
      ..limits,
      compilation: { ..limits.compilation, work: work - 1, },
    }
    assert_true(
      @program_check.check_parsed_scoped(
        program,
        environment,
        TemplateOnly,
        None,
        exhausted,
      )
      is TemplateOnly(Unresolved(_) | Rejected(_)),
    )
  }
}
