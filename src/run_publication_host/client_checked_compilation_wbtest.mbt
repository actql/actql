///|
/// Actual retained parser/binder/checker output, without a Host or Resource
/// fixture. Backend funding and later Run adoption remain separate tests.
fn retained_compilation_fixture(
  supplied : Int,
) -> (@checked.CheckedProgram, @syntax.Program, @checked.CheckEnvironment) raise {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let declarations = @parameter.read_declarations(
    Some(
      scalar_profile_cursor("{\"id\":{\"type\":\"number\",\"nullable\":false}}"),
    ),
    {
      max_parameters: 100,
      max_nodes: 1000,
      max_depth: 32,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    parameter_declarations=Some(declarations),
  ).unwrap()
  let program = @source_frontend.lower("SELECT @id AS id", Sql, Some(context)).unwrap().program.unwrap()
  let input = @checked.prepare_parsed_check_input(
    program,
    environment,
    Some(scalar_profile_cursor("{\"id\":" + supplied.to_string() + "}")),
    [],
    client_standard_program_preparation_limits().checking,
  ).unwrap()
  let prelude = @checked.observe_parsed_check_prelude(input).0.unwrap()
  let registry_input = @checked.prepare_parsed_catalog_input(prelude).unwrap()
  let registry = @checked.observe_parsed_check_registry(registry_input).0.unwrap()
  guard @checked.finish_parsed_check_registry(registry).unwrap()
    is Checked(checked) else {
    fail("the original ordinary parameter query did not finish checking")
  }
  assert_true(
    @checked.finish_parsed_check_registry(registry) is Err(AlreadyConsumed),
  )
  (checked, program, environment)
}

///|
fn compile_retained_fixture(
  checked : @checked.CheckedProgram,
  limits : ClientProgramPreparationLimits,
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  prepare_checked_effect_free_client_program(
    checked,
    limits.lowering,
    max_parameters=limits.max_parameters,
    max_parameter_name_bytes=limits.max_parameter_name_bytes,
    max_tasks=limits.max_tasks,
    max_graph_work=limits.max_graph_work,
  )
}

///|
test "retained check compilation keeps the exact Program Environment graph and bound parameters" {
  let (checked, source, environment) = retained_compilation_fixture(7)
  assert_false(@checked.checked_program_has_effects(checked))
  let prepared = compile_retained_fixture(
    checked,
    client_standard_program_preparation_limits(),
  ).unwrap()
  // A second checker result cannot stand in for this original, even if its
  // source and semantic identity would otherwise compare equal.
  assert_true(physical_equal(@strategy.graph_program(prepared.graph), checked))
  assert_true(physical_equal(prepared.source, source))
  assert_true(physical_equal(@checked.checked_source_program(checked), source))
  assert_true(
    physical_equal(
      @checked.checked_environment(checked),
      @checked.checking_environment_wire(environment),
    ),
  )
  assert_eq(
    prepared_client_check_environment_cid(prepared),
    @checked.checking_environment_cid(environment),
  )
  assert_eq(
    local_parameter_values_identity(prepared),
    @context.program_identity_parameter_values_cid(
      @checked.source_identity(checked),
    ),
  )
  assert_eq(@strategy.graph_task_count(prepared.graph), 1)
  assert_eq(prepared_client_result_count(prepared), 1)
  let task = @strategy.graph_task_owner(prepared.graph, 0).unwrap()
  assert_eq(
    @values.canonical_scalar_text(
      @lower.parameter_value(task, "id").unwrap(),
      32,
    ),
    Some("7"),
  )
}

///|
test "retained compilation never substitutes another independently checked parameter binding" {
  let (first, first_source, _) = retained_compilation_fixture(7)
  let (second, second_source, _) = retained_compilation_fixture(9)
  let limits = client_standard_program_preparation_limits()
  let a = compile_retained_fixture(first, limits).unwrap()
  let b = compile_retained_fixture(second, limits).unwrap()
  assert_false(physical_equal(first, second))
  assert_false(physical_equal(first_source, second_source))
  assert_true(physical_equal(@strategy.graph_program(a.graph), first))
  assert_true(physical_equal(@strategy.graph_program(b.graph), second))
  assert_true(physical_equal(a.source, first_source))
  assert_true(physical_equal(b.source, second_source))
  assert_false(
    local_parameter_values_identity(a) == local_parameter_values_identity(b),
  )
  for (owner, expected) in [(a, "7"), (b, "9")] {
    let task = @strategy.graph_task_owner(owner.graph, 0).unwrap()
    assert_eq(
      @values.canonical_scalar_text(
        @lower.parameter_value(task, "id").unwrap(),
        32,
      ),
      Some(expected),
    )
  }
}

///|
test "retained check still applies original lowering binding and graph bounds" {
  let (checked, _, _) = retained_compilation_fixture(7)
  let limits = client_standard_program_preparation_limits()
  assert_true(
    compile_retained_fixture(checked, {
      ..limits,
      lowering: { ..limits.lowering, max_work: 0, },
    })
    is Err(Lowering(_)),
  )
  assert_true(
    compile_retained_fixture(checked, { ..limits, max_parameters: 0, })
    is Err(Binding(_)),
  )
  assert_true(
    compile_retained_fixture(checked, { ..limits, max_tasks: 0, })
    is Err(Graph(_)),
  )
}

///|
test "retained Effect check cannot enter the pure compilation continuation" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let effect = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let checked = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(effect),
  )
  assert_true(@checked.checked_program_has_effects(checked))
  assert_true(
    compile_retained_fixture(checked, limits.program)
    is Err(EffectNotSupported("source")),
  )
  assert_eq(prepared_client_effect_result_count(effect), 1)
}
