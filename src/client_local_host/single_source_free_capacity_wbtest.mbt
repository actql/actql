///|
fn single_source_free_capacity_prepared(
  document? : String = (
    #|{"version":"actql/0.1","id":"source-free-capacity","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
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
test "single source-free quote retains the existing admission ceiling without opening a Run" {
  let prepared = single_source_free_capacity_prepared()
  let assets = @publication_host.client_local_product_assets()
  let limits = single_source_free_local_ledger_limits(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(limits.attempts, 1)
  assert_eq(limits.holdings, 1)
  assert_eq(limits.transfer_bytes, 1000000L)
  assert_eq(limits.execution_bytes, 536870912L)
  assert_true(limits.retained_bytes >= 200000000L)
  assert_true(limits.retained_bytes <= 536870912L)
}

///|
test "single source-free quote refuses Source acquisition and foreign registry before supply" {
  let assets = @publication_host.client_local_product_assets()
  assert_true(
    single_source_free_local_ledger_limits(
      single_source_free_capacity_prepared(
        document=source_query_original_document,
      ),
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
  assert_true(
    single_source_free_local_ledger_limits(
      single_source_free_capacity_prepared(),
      "{}",
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
}
