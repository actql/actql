///|
fn full_sequence_local_prepared() -> @publication_host.PreparedClientProgram {
  let assets = @publication_host.client_local_product_assets()
  let body = @json.parse(assets.environment) catch {
    _ => abort("original bundled Environment JSON invalid")
  }
  guard body is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    abort("original bundled Environment identity missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    (
      #|{"version":"actql/0.1","id":"full-sequence-original","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
    ),
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "Local generated execution consumes the original compilation full sequence" {
  let prepared = full_sequence_local_prepared()
  let limits = @publication_host.prepared_client_values_sequence_limits(
    prepared,
  )
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  ignore(
    @publication_host.issue_prepared_client_values_compilation(
      prepared, manifests, limits, 1000, 1000, 1000000, 100000, 100,
    ).unwrap(),
  )
  let original = @publication_host.prepare_prepared_client_full_sequence(
    prepared, 0, limits,
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = prepare_client_local_sequences(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(sequences.length(), 1)
  assert_true(
    physical_equal(
      original,
      @execution.generated_prepared_sequence(sequences[0]),
    ),
  )
  let foreign = full_sequence_local_prepared()
  let other = prepare_client_local_sequences(
    foreign,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_false(
    physical_equal(original, @execution.generated_prepared_sequence(other[0])),
  )
  let tighter = @publication_host.with_prepared_client_values_row_limit(
    prepared, 1,
  ).unwrap()
  assert_true(
    prepare_client_local_sequences(
      tighter,
      asset_contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
}
