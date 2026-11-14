///|
test "source-free work bounds Fragment preparation after independent Program checking" {
  let assets = @publication_host.client_local_product_assets()
  let wire = @json.parse(assets.environment) catch {
    _ => abort("invalid original bundled environment")
  }
  guard wire is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    abort("missing original environment identity")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // This same original Program is already parsed and checked independently
  // of either installed work selection below; no compiler allowance changes.
  let prepared = @publication_host.prepare_effect_free_client_program(
    (
      #|{"version":"actql/0.1","id":"source-free-work-boundary","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"from":"seed","derive":{"next":"id + 1"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"s","result":"out"}}}}
    ),
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let compilation = @publication_host.client_standard_pure_compilation_limits()
  let sequence = @publication_host.prepare_prepared_client_full_sequence(
    prepared,
    0,
    client_local_owner_sequence_limits(Pure(prepared)),
  ).unwrap()
  let roots : @lower.RootLimits = {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }
  assert_true(
    @lower.prepare_fragment_pipeline(sequence, 1, { ..roots, max_work: 1, })
    is Err(@lower.RootLimit),
  )
  let fragment = @lower.prepare_fragment_pipeline(sequence, 1, roots).unwrap()
  assert_true(
    @lower.prepare_demand(@lower.fragment_pipeline_roots(fragment), {
      max_roots: 100,
      max_nodes: compilation.max_nodes,
      max_work: 1,
      max_text_bytes: compilation.max_wire_bytes,
      max_links: compilation.max_nodes,
    })
    is Err(@lower.DemandLimit),
  )
  let prepare = fn(work) {
    prepare_client_local_sequences_owned(
      Pure(prepared),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      source_free_max_work=Some(work),
      compilation_limits=Some(compilation),
    )
  }
  assert_eq(client_local_source_free_max_work(Some(1)), Some(1))
  assert_true(prepare(1) is Err(Unsupported))
  assert_eq(prepare(100000).unwrap().length(), 1)
}
