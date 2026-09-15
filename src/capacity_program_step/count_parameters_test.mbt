///|
test "prepared count values share interpretation without sharing pipeline authority" {
  let declaration_text = "{\"n\":{\"type\":\"number\",\"default\":7},\"dt\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"3ms\"}}"
  let limits : @parameter.DeclarationLimits = {
    max_parameters: 2,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  let declarations = @parameter.read_declarations(
    Some(cursor(declaration_text)),
    limits,
  ).unwrap()
  let values = count_values(declarations, None)
  // Two entries, three name bytes and three duration-token bytes.
  let prepared = @capacity_program_step.prepare_count_parameters(
    values,
    max_work=2,
    max_text_bytes=6,
  ).unwrap()
  assert_eq(@capacity_program_step.count_parameters_usage(prepared), (2, 6))
  assert_true(
    @capacity_program_step.prepare_count_parameters(
      values,
      max_work=1,
      max_text_bytes=6,
    )
    is Err(BindingWorkLimit),
  )
  assert_true(
    @capacity_program_step.prepare_count_parameters(
      values,
      max_work=2,
      max_text_bytes=5,
    )
    is Err(BindingTextLimit),
  )
  let p = pipeline(
    "[{\"take\":{\"$param\":\"n\"}}]",
    parameters=Some(declarations),
  )
  let attached = @capacity_program_step.bind_prepared_parameters(p, prepared).unwrap()
  assert_eq(@capacity_program_step.binding_usage(attached), (0, 0))
  assert_true(
    physical_equal(@capacity_program_step.parameter_values(attached), values),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.binding_parameters(attached),
      prepared,
    ),
  )
  let direct = @capacity_program_step.bind_parameters(
    p,
    values,
    max_work=2,
    max_text_bytes=6,
  ).unwrap()
  assert_eq(@capacity_program_step.binding_usage(direct), (2, 6))
  let a = @capacity_program_step.derive_bound(
    p,
    0,
    [],
    derive_limits(),
    bindings=Some(attached),
  ).unwrap()
  let b = @capacity_program_step.derive_bound(
    p,
    0,
    [],
    derive_limits(),
    bindings=Some(direct),
  ).unwrap()
  assert_eq(bound_id(a.bound), bound_id(b.bound))
  assert_eq(
    @wire.value(
      @wire.program_proof_witness(@capacity_program_step.checked_proof(a.bound)),
    ),
    7L,
  )

  let window = window_pipeline(
    "sliding",
    "\"size\":10,\"step\":{\"$param\":\"dt\"}",
    false,
    parameters=Some(declarations),
  )
  let window_binding = @capacity_program_step.bind_prepared_parameters(
    window, prepared,
  ).unwrap()
  assert_true(
    physical_equal(
      @capacity_program_step.binding_parameters(window_binding),
      prepared,
    ),
  )
  let seed = @capacity_program_step.derive_bound(window, 0, [], derive_limits()).unwrap().bound
  let expanded = @capacity_program_step.derive_bound(
    window,
    1,
    [StepInput(seed)],
    derive_limits(),
    bindings=Some(window_binding),
  ).unwrap()
  assert_eq(
    @wire.value(
      @wire.program_proof_witness(
        @capacity_program_step.checked_proof(expanded.bound),
      ),
    ),
    12L,
  )
  assert_true(
    @capacity_program_step.derive_bound(
      window,
      1,
      [StepInput(seed)],
      derive_limits(),
      bindings=Some(attached),
    )
    is Err(Application(BindingOwnerMismatch)),
  )

  let foreign_declarations = @parameter.read_declarations(
    Some(cursor(declaration_text)),
    limits,
  ).unwrap()
  let foreign = pipeline(
    "[{\"take\":{\"$param\":\"n\"}}]",
    parameters=Some(foreign_declarations),
  )
  assert_true(
    @capacity_program_step.bind_prepared_parameters(foreign, prepared)
    is Err(BindingOwnerMismatch),
  )
  let changed = @capacity_program_step.prepare_count_parameters(
    count_values(declarations, Some("{\"n\":9}")),
    max_work=2,
    max_text_bytes=6,
  ).unwrap()
  let rebound = @capacity_program_step.bind_prepared_parameters(p, changed).unwrap()
  assert_true(
    @capacity_program_step.check_with_inputs(
      p,
      0,
      @capacity_program_step.checked_proof(a.bound),
      [],
      bindings=Some(rebound),
    )
    is Err(_),
  )
}
