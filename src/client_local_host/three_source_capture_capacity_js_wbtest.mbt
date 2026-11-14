///|
// Actual three-occurrence frontend/Plan/capacity connection. The same static
// Source backing is repeated, but each original acquisition and debt remains
// separate. No physical Source, Native library or installed Host is opened.
test "three Source occurrences use the complete original capture capacity inventory" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication =
    #|{"environmentCid":"sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8","aliases":[{"name":"left_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"},{"name":"middle_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"},{"name":"right_records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"}]}
  let context = @source_publication.bind_published_query_context(
    environment,
    publication,
    None,
  ).unwrap()
  let lowered = @frontend.lower(
    "SELECT l.id AS id FROM left_records AS l JOIN middle_records AS m ON l.id = m.id MAX_OUTPUT_ROWS 4 JOIN right_records AS r ON l.id = r.id MAX_OUTPUT_ROWS 4",
    Sql,
    Some(context),
  ).unwrap()
  let prepared = @publication_host.prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "three-original-Source-occurrences",
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sources = [0, 1, 2].map(stage => {
    prepare_installed_catalog_whole_source_capacity(
      prepared,
      unfiltered_join_whole_input(prepared, request, stage),
      contracts,
      installed_row_input_policy(4, 4096, 256, 16, 4),
    ).unwrap()
  })
  assert_true(installed_managed_owner_shape_supported(Pure(prepared), false))
  match
    @strategy.prepare_source_inputs_dag(
      @publication_host.prepared_client_graph(prepared),
      sources.map(source => source.original),
    ) {
    Ok(_) => ()
    Err(_) =>
      fail("three-source Plan: physical Source input graph refuses originals")
  }
  match
    prepare_client_local_sequences_owned(
      Pure(prepared),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ) {
    Ok(_) => ()
    Err(_) =>
      fail("three-source Plan: original generated sequence preparation refused")
  }
  let construct = sources => {
    prepare_installed_managed_whole_sources_plan(
      prepared,
      request,
      sources,
      [4096L, 4096L, 4096L],
      [2048L, 2048L, 2048L],
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      retained_output=true,
      provider_factory=_ => [],
      runtime_admission=true,
    )
  }
  let plan = match construct(sources) {
    Ok(plan) => plan
    Err(Unsupported) => fail("three-source Plan: unsupported original shape")
    Err(ForeignOriginal) => fail("three-source Plan: foreign original binding")
    Err(InsufficientCapacity) =>
      fail("three-source Plan: insufficient original capacity")
    Err(_) => fail("three-source Plan: another typed owner refusal")
  }
  assert_eq(plan.whole_sources.length(), 3)
  let direct = plan.direct_occurrences.unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_count(direct),
    3,
  )
  for slot in 0..<3 {
    assert_true(physical_equal(plan.whole_sources[slot], sources[slot]))
    assert_eq(
      @publication_host.client_direct_acquisition_occurrence_at(direct, slot),
      Some((slot, 0, slot)),
    )
  }
  let total = sources.fold(init=0L, (total, source) => {
    total + source.complete.retained_bytes
  })
  assert_true(plan.limits.retained_bytes >= total)
  assert_true(construct([sources[0], sources[1]]) is Err(_))
  assert_true(
    construct([sources[1], sources[0], sources[2]]) is Err(ForeignOriginal),
  )
}
