///|
// The published SQL and original checked Source schema exercise the real Node
// constructor. This component supplies no Account, transport or physical ACK.
test "Node Whole Source Plan uses finite runtime admission for set output expressions" {
  let environment = @publication_host.admit_client_check_environment(
    request_capture_bridge_source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[{\"name\":\"records\",\"sourceRef\":\"connector://crm/main/r#v\",\"sourceViewContractCid\":\"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3\",\"schemaContractCid\":\"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4\"}]}"
  let prepared = match
    client_program_prepare_source_computation_with_parameters(
      "WITH chosen AS (SELECT id FROM records WHERE amount >= 20 UNION ALL SELECT id FROM records WHERE amount IS NULL ORDER BY 0 - id LIMIT 2) SELECT id FROM chosen ORDER BY id",
      "sql",
      environment,
      publication,
      None,
      None,
      false,
      [],
    ) {
    SourcePure(Prepared(value)) => value
    _ => fail("original set output Source preparation")
  }
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "set-output-expression",
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  guard @client_local_host.select_installed_source_input(
      prepared, request, 0, 0,
    ).unwrap()
    is @acquisition.WholeInputRoute(original) else {
    fail("set expression requires the same complete Source")
  }
  let source = @client_local_host.prepare_installed_catalog_whole_source_capacity(
    prepared,
    original,
    contracts,
    @client_local_host.installed_row_input_policy(
      10000, 10000000, 110101, 2, 10000,
    ),
  ).unwrap()
  let single = client_program_prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    10000000L,
    239908928L,
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
    false,
  ).unwrap()
  let plural = client_program_prepare_installed_managed_whole_sources_plan(
    prepared,
    request,
    [source],
    [10000000L],
    [239908928L],
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
    false,
  ).unwrap()
  assert_eq(
    client_program_prepared_installed_whole_source_requirements(single),
    client_program_prepared_installed_whole_source_requirements(plural),
  )
  assert_true(
    client_program_prepare_installed_managed_whole_source_plan_at_query_time(
      prepared,
      request,
      source,
      10000000L,
      239908928L,
      contracts,
      assets.values,
      Some(assets.fragment),
      None,
      false,
      None,
    )
    is Err(@client_local_host.ForeignOriginal),
  )
  assert_true(
    client_program_prepare_installed_managed_whole_sources_plan_at_query_time(
      prepared,
      request,
      [source],
      [10000000L],
      [239908928L],
      contracts,
      assets.values,
      Some(assets.fragment),
      None,
      false,
      None,
    )
    is Err(@client_local_host.ForeignOriginal),
  )
}
