///|
fn bound_context(
  p : @pipeline.CheckedPipeline,
  values : @parameter.BoundValues?,
) -> @pipeline.BoundAuthorGuards {
  @pipeline.bind_author_guards(
    @pipeline.collect_author_guards(p, max_work=1000, max_text_bytes=1000).unwrap(),
    values,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
}

///|
test "Program proof bindings cannot be substituted across bound guard contexts" {
  let d = count_declarations()
  let p = pipeline("[{\"take\":{\"$param\":\"n\"}}]", parameters=Some(d))
  let values = count_values(d, None)
  let bindings = @capacity_program_step.bind_parameters(
    p,
    values,
    max_work=2,
    max_text_bytes=7,
  ).unwrap()
  let claim = proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let app = @capacity_program_step.check_with_inputs(
    p,
    0,
    claim,
    [],
    bindings=Some(bindings),
  ).unwrap()
  let claims = program_claims([claim])
  let applications = @capacity_program_step.check_applications(
    claims,
    [app],
    max_work=10,
  ).unwrap()
  let context = bound_context(p, Some(values))
  let checked = @capacity_program_step.check_guard_bindings(
    applications,
    context,
    max_work=1,
  ).unwrap()
  assert_eq(@capacity_program_step.guard_application_count(checked), 1)
  assert_eq(@capacity_program_step.guard_application_work(checked), 1)
  assert_true(
    physical_equal(
      @capacity_program_step.guard_application_source(checked),
      applications,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.guard_application_context(checked),
      context,
    ),
  )
  for supplied in [None, Some("{\"n\":9}")] {
    // Even equal-valued fresh collections do not establish the same invocation owner.
    let different = bound_context(p, Some(count_values(d, supplied)))
    assert_true(
      @capacity_program_step.check_guard_bindings(
        applications,
        different,
        max_work=1,
      )
      is Err(BindingMismatch(0)),
    )
  }
  assert_true(
    @capacity_program_step.check_guard_bindings(
      applications,
      context,
      max_work=0,
    )
    is Err(WorkLimit),
  )
  assert_true(
    @capacity_program_step.check_guard_bindings(
      applications,
      context,
      max_work=-1,
    )
    is Err(InvalidLimits),
  )
}

///|
test "binding-independent proofs and foreign producers retain distinct coverage" {
  let p = pipeline("[{\"take\":7}]")
  let claim = proof("actql.bound.take", 7, "{\"maximum\":7,\"op\":\"clamp\"}")
  let app = @capacity_program_step.check(p, 0, claim).unwrap()
  let applications = @capacity_program_step.check_applications(
    program_claims([claim]),
    [app],
    max_work=10,
  ).unwrap()
  let same = @capacity_program_step.check_guard_bindings(
    applications,
    bound_context(p, None),
    max_work=1,
  ).unwrap()
  assert_eq(@capacity_program_step.guard_application_count(same), 1)
  let other = @capacity_program_step.check_guard_bindings(
    applications,
    bound_context(pipeline("[{\"take\":7}]"), None),
    max_work=1,
  ).unwrap()
  assert_eq(@capacity_program_step.guard_application_count(other), 0)
  assert_eq(@capacity_program_step.guard_application_work(other), 1)
}
