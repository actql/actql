///|
// Existing checked Mapping and standard Host limits. These requirement tests
// issue no operational admission, Allow, Preview, imported child or Ledger.
fn installed_effect_managed_fixture(
  rows? : String = "[{\"id\":1}]",
) -> @publication_host.PreparedClientEffectComputation {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"installed-effect-managed","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let document = document.replace(
    old="\"rows\":[{\"id\":1}]",
    new="\"rows\":" + rows,
  )
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
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let prepared = installed_effect_managed_fixture()
  assert_true(installed_managed_owner_shape_supported(Effect(prepared), false))
  let limits = installed_effect_managed_run_requirements(
    prepared,
    [],
    "",
    "",
    [],
    [],
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  // The same finite runtime policy as the source-free pure owner; Effect
  // ownership does not turn the retention ceiling into an upfront reservation.
  assert_eq(limits, [100000L, 1L, 1L, 1000000L, 536870912L, 536870912L])
  assert_eq(@publication_host.prepared_client_effect_result_count(prepared), 1)
}

///|
test "installed Effect requirements do not relabel ordinary work as a Mock Model or supplied Source" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
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
      source_contracts,
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
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
}
