///|
// Existing checked environment with an independently authored source-free
// Program. These quote tests supply no operational admission or test Ledger.
fn source_free_managed_prepared_fixture(
  document? : String = (
    #|{"version":"actql/0.1","id":"source-free-managed","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  ),
) -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:4ea01561b9ac9815baaf04a81cff8260c8a47c56f19828b5889cf45ec1436e78",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "source-free managed Run quotes the existing Local output envelope without a Source" {
  let prepared = source_free_managed_prepared_fixture()
  assert_true(installed_managed_run_purpose_supported(prepared))
  let required = installed_managed_run_requirements(
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
  // The original installed Local limits: one task/holding, one 1MB transfer,
  // 200MB minimum retained allowance and unchanged 512MiB execution ceiling.
  assert_eq(required, [100000L, 1L, 1L, 1000000L, 200000000L, 536870912L])
}

///|
test "source-free managed Run refuses supplied Source transport and changed registry" {
  let prepared = source_free_managed_prepared_fixture()
  assert_true(
    installed_managed_run_requirements(
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
  assert_true(
    installed_managed_run_requirements(
      prepared,
      [],
      "",
      "",
      [],
      [],
      "{}",
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
}

///|
test "managed Run requires the actual declaration for a single Source instead of treating it as source-free" {
  let prepared = installed_source_read_prepared_fixture()
  assert_true(installed_managed_run_purpose_supported(prepared))
  assert_true(
    installed_managed_run_requirements(
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
}

///|
test "local Mock quote does not relabel ordinary Compute or serialized Model as its purpose" {
  let plain = source_free_managed_prepared_fixture()
  let (serialized, _, _, _) = original_prefix_execution_fixture()
  for prepared in [plain, serialized] {
    assert_true(!installed_managed_run_shape_supported(prepared, true))
    assert_true(
      installed_mock_model_run_requirements(
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
  }
  // The existing Compute entry is unchanged, not made dependent on a Model
  // purpose or granted one merely by this shared requirement calculation.
  assert_true(installed_managed_run_purpose_supported(plain))
}
