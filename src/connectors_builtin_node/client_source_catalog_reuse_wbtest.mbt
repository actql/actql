///|
test "actual Source lowering retains its exact configured Catalog for parsed preparation" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let catalogs : Array[@program_check.PreparedSourceCatalog] = []
  let lowered = client_program_lower_source(
    "SELECT 1 AS id",
    "sql",
    environment,
    publication,
    None,
    source_catalog_out=Some(catalogs),
  ).unwrap()
  assert_eq(catalogs.length(), 1)
  assert_true(
    physical_equal(
      @program_check.source_catalog_owner(catalogs[0]),
      environment,
    ),
  )
  let parsed = client_source_program(lowered).unwrap()
  let retained = @publication_host.prepare_parsed_effect_free_client_program(
    parsed,
    environment,
    None,
    client_program_standard_limits(),
    source_catalog=Some(catalogs[0]),
  ).unwrap()
  let ordinary = client_program_prepare_source_computation_with_parameters(
    "SELECT 1 AS id",
    "sql",
    environment,
    publication,
    None,
    None,
    false,
    [],
  )
  guard ordinary is SourcePure(Prepared(value)) else {
    fail("ordinary Source preparation must retain its original Catalog")
  }
  assert_eq(
    @program_check.unit_definition_cid(
      @strategy.graph_program(@publication_host.prepared_client_graph(value)),
      0,
    ),
    @program_check.unit_definition_cid(
      @strategy.graph_program(@publication_host.prepared_client_graph(retained)),
      0,
    ),
  )
}
