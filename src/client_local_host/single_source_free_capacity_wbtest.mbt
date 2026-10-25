///|
fn single_source_free_capacity_prepared(
  document? : String = (
    #|{"version":"actql/0.1","id":"source-free-capacity","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  ),
) -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
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
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = single_source_free_local_ledger_limits(
    prepared,
    asset_contracts,
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
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(
    single_source_free_local_ledger_limits(
      single_source_free_capacity_prepared(
        document=source_query_original_document,
      ),
      asset_contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
  assert_true(
    prepare_installed_sequence_contracts(
      "{}",
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Err(Unsupported),
  )
}

///|
test "the original public UNION graph is outside the single-task quote before any physical supply" {
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("ordinary original product Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let context = @frontend.bind_query_context([], cid).unwrap()
  let original = @frontend.lower(
    "SELECT 1 AS n UNION ALL SELECT 2 AS n",
    @frontend.Sql,
    Some(context),
  ).unwrap()
  let prepared = @publication_host.prepare_parsed_effect_free_client_program(
    original.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  // Six authored stages retain eight physical tasks after the existing
  // checked carrier splitter; a stage count is not a task count.
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 0)
  assert_true(@strategy.graph_source_free_inputs_complete(graph))
  assert_false(@strategy.graph_program_has_effects(graph))
  assert_true(
    @publication_host.issue_prepared_client_local_normalization(prepared)
    is Ok(_),
  )
  let sequences = prepare_client_local_sequences(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(sequences.length(), 8)
  assert_true(
    single_source_free_local_ledger_limits(
      prepared,
      asset_contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
}
