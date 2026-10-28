///|
fn command_preparation_publication(
  environment : @checked.CheckEnvironment,
  limits : ClientEffectComputationLimits,
) -> @update_targets.CommandTargetPublication {
  let registry = @environment.check_contract_registry(
    @checked.checking_environment_wire(environment),
    limits.mapping,
  ).unwrap()
  let catalogs = @environment.check_catalog_contents(registry, limits.mapping).unwrap()
  // This namespace-transfer counter deliberately selects no Command alias.
  // It proves the original receiver, not a target issuer or Command capture.
  @update_targets.bind_command_target_publication(
    catalogs,
    [],
    { max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
    1000,
  ).unwrap()
}

///|
test "Effect preparation retains the exact original Command publication" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let publication = command_preparation_publication(environment, limits)
  let equal_namespace = command_preparation_publication(environment, limits)
  assert_false(physical_equal(publication, equal_namespace))
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    command_targets=Some(publication),
  ).unwrap()
  let original = prepared_client_effect_command_target_publication(prepared).unwrap()
  assert_true(physical_equal(original, publication))
  assert_false(physical_equal(original, equal_namespace))
  assert_true(
    physical_equal(
      @update_targets.command_target_publication_environment(original),
      @checked.checking_environment_wire(environment),
    ),
  )
}

///|
test "parsed Effect preparation preserves source and rejects an equal-CID foreign publication" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let (_, foreign_environment, _) = local_update_normalization_fixture()
  assert_eq(
    @checked.checking_environment_cid(environment),
    @checked.checking_environment_cid(foreign_environment),
  )
  let parsed = @syntax.parse(
    document,
    limits.program.checking.input,
    format=Json,
  ).unwrap()
  let original = command_preparation_publication(environment, limits)
  let prepared = prepare_parsed_client_effect_computation(
    parsed,
    environment,
    None,
    [],
    limits,
    command_targets=Some(original),
  ).unwrap()
  assert_true(
    physical_equal(prepared_client_effect_computation_source(prepared), parsed),
  )
  assert_true(
    physical_equal(
      prepared_client_effect_command_target_publication(prepared).unwrap(),
      original,
    ),
  )
  let foreign = command_preparation_publication(foreign_environment, limits)
  assert_true(
    prepare_parsed_client_effect_computation(
      parsed,
      environment,
      None,
      [],
      limits,
      command_targets=Some(foreign),
    )
    is Err(TargetSelection(ForeignEnvironment)),
  )
}

///|
test "retained static Effect compilation preserves original Command environment and refusal order" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let (_, foreign_environment, _) = local_update_normalization_fixture()
  let candidate = retained_static_effect_fixture(document, environment, None, limits)
  let original = command_preparation_publication(environment, limits)
  let prepared = prepare_static_client_effect_computation(
    candidate,
    limits.program,
    limits.max_mapping_work,
    command_targets=Some(original),
  ).unwrap()
  assert_true(
    physical_equal(
      prepared_client_effect_command_target_publication(prepared).unwrap(),
      original,
    ),
  )
  let foreign = command_preparation_publication(foreign_environment, limits)
  assert_eq(
    @checked.checking_environment_cid(environment),
    @checked.checking_environment_cid(foreign_environment),
  )
  assert_true(
    prepare_static_client_effect_computation(
      candidate,
      { ..limits.program, max_tasks: 0, },
      limits.max_mapping_work,
      command_targets=Some(foreign),
    )
    is Err(TargetSelection(ForeignEnvironment)),
  )
  let (parsed, _) = @checked.effect_program_static_original_input(candidate)
  assert_true(
    prepare_parsed_client_effect_computation(
      parsed,
      environment,
      None,
      [],
      { ..limits, max_members: 0, },
      command_targets=Some(foreign),
    )
    is Err(TargetSelection(ForeignEnvironment)),
  )
}

///|
test "absent Command publication preserves original static identities" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let original = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    prepared_client_effect_command_target_publication(original) is None,
  )
  let publication = command_preparation_publication(environment, limits)
  let retained = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    command_targets=Some(publication),
  ).unwrap()
  assert_eq(
    prepared_client_effect_computation_definition_cid(original),
    prepared_client_effect_computation_definition_cid(retained),
  )
  assert_eq(
    prepared_client_effect_computation_semantics_cid(original),
    prepared_client_effect_computation_semantics_cid(retained),
  )
  assert_eq(
    prepared_client_effect_target_selections(original),
    prepared_client_effect_target_selections(retained),
  )
}
