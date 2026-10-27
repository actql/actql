///|
test "public checker retains original Source declarations through actual topology and binding" {
  let (_, program, environment, _, limits) = public_input_fixture()
  let source = @stages.prepare(program, {
    max_parameters: 1,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let (source, original_binding) = @stages.prepare_bindings(source, None, {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  })
  guard original_binding is Ok(Ready(original_values)) else {
    fail("original default")
  }
  let checked = public_checked(
    @program_check.check_parsed(
      program,
      environment,
      None,
      limits,
      source_preparation=Some(source),
    ),
  )
  let pipeline = @program_check.unit_pipeline(checked, 0).unwrap()
  assert_true(
    physical_equal(
      @pipeline.parameters(pipeline).unwrap(),
      @stages.declarations(source),
    ),
  )
  let identity = @context.program_identity_stage_at(
    @program_check.source_identity(checked),
    0,
  ).unwrap()
  let used = @context.stage_identity_parameter_values(identity)
  assert_true(
    physical_equal(
      @parameter_refs.used_value_at(used, 0).unwrap(),
      @parameters.bound_value_at(original_values, 0).unwrap(),
    ),
  )
  // Equal freshly parsed source remains a distinct owner and uses full reads.
  let (_, other_program, _, _, _) = public_input_fixture()
  let other = public_checked(
    @program_check.check_parsed(
      other_program,
      environment,
      None,
      limits,
      source_preparation=Some(source),
    ),
  )
  assert_true(
    !physical_equal(
      @pipeline.parameters(@program_check.unit_pipeline(other, 0).unwrap()).unwrap(),
      @stages.declarations(source),
    ),
  )
}

///|
test "template original Source forwarding retains scope and rejects supplied values before reuse" {
  let (program, environment, limits) = template_fixture()
  let source = @stages.prepare(program, {
    max_parameters: 1,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let prepared = @program_check.prepare_template_declarations(
    program,
    environment,
    limits,
    source_preparation=Some(source),
  ).unwrap()
  assert_true(
    physical_equal(
      @results.wiring_source(
        @program_check.template_declarations_wiring(prepared),
      ),
      source,
    ),
  )
  assert_true(
    @program_check.check_parsed_scoped(
      program,
      environment,
      TemplateOnly,
      Some(@syntax.program_body(program)),
      limits,
      source_preparation=Some(source),
    )
    is InvalidRequest(BindingsInTemplateScope),
  )
}
