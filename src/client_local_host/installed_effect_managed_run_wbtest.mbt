///|
// Existing checked Mapping and standard Host limits. These requirement tests
// issue no operational admission, Allow, Preview, imported child or Ledger.
fn installed_effect_managed_fixture() -> @publication_host.PreparedClientEffectComputation {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"installed-effect-managed","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
}

///|
test "installed Effect requirements retain the checked Effect owner without a pure cast" {
  let prepared = installed_effect_managed_fixture()
  assert_true(installed_managed_owner_shape_supported(Effect(prepared), false))
  let limits = installed_effect_managed_run_requirements(
    prepared,
    [],
    "",
    "",
    [],
    [],
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_eq(limits, [100000L, 1L, 1L, 1000000L, 200000000L, 536870912L])
  assert_eq(@publication_host.prepared_client_effect_result_count(prepared), 1)
}

///|
test "installed Effect requirements do not relabel ordinary work as a Mock Model or supplied Source" {
  let prepared = installed_effect_managed_fixture()
  assert_true(!installed_managed_owner_shape_supported(Effect(prepared), true))
  assert_true(
    installed_effect_mock_model_run_requirements(
      prepared,
      [],
      "",
      "",
      [],
      [],
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
  assert_true(
    installed_effect_managed_run_requirements(
      prepared,
      [],
      "",
      "",
      [1L],
      [],
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
}
