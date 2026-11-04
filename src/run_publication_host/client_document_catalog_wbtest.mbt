///|
test "document preparation consumes the same original Catalog without changing query identity" {
  let environment = admit_client_check_environment(
    multi_source_environment,
    "sha256:c9cf17f3e181c97a69e3419d4543e98c9a04af6da9490b359511a673a64c49a7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let catalog = @checked.prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let limits = client_standard_program_preparation_limits()
  let original = prepare_effect_free_client_program(
    multi_source_program,
    Json,
    environment,
    None,
    limits,
  ).unwrap()
  let reused = prepare_effect_free_client_program(
    multi_source_program,
    Json,
    environment,
    None,
    limits,
    source_catalog=Some(catalog),
  ).unwrap()
  assert_eq(
    prepared_client_identity(reused),
    prepared_client_identity(original),
  )
  assert_eq(
    prepared_client_program_semantics_cid(reused),
    prepared_client_program_semantics_cid(original),
  )
  assert_eq(prepared_client_acquisition_count(reused), 2)
  let foreign = @checked.checking_environment(
    @checked.checking_environment_wire(environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  assert_true(
    prepare_effect_free_client_program(
      multi_source_program,
      Json,
      foreign,
      None,
      limits,
      source_catalog=Some(catalog),
    )
    is Err(Check(_)),
  )
  assert_true(
    prepare_effect_free_client_program(
      multi_source_program,
      Json,
      environment,
      None,
      {
        ..limits,
        checking: {
          ..limits.checking,
          input: {
            ..limits.checking.input,
            source: { ..limits.checking.input.source, max_input_bytes: 1, },
          },
        },
      },
      source_catalog=Some(catalog),
    )
    is Err(Syntax(_)),
  )
}

///|
test "Effect document preparation forwards the original Catalog and retains the same computation" {
  let (document, environment, limits) = client_composed_effect_base_fixture()
  let catalog = @checked.prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let original = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let reused = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    source_catalog=Some(catalog),
  ).unwrap()
  assert_eq(
    prepared_client_effect_identity(reused),
    prepared_client_effect_identity(original),
  )
  assert_eq(
    prepared_client_effect_computation_semantics_cid(reused),
    prepared_client_effect_computation_semantics_cid(original),
  )
  let foreign = @checked.checking_environment(
    @checked.checking_environment_wire(environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  assert_true(
    prepare_client_effect_computation(
      document,
      Json,
      foreign,
      None,
      [],
      limits,
      source_catalog=Some(catalog),
    )
    is Err(Candidate(_)),
  )
}
