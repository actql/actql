///|
test "Request compiler ceilings do not become every small Fragment runtime body" {
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
  let prepared = @publication_host.prepare_effect_free_client_program(
    (
      #|{"version":"actql/0.1","id":"fragment-codec-demand","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"from":"seed","derive":{"next":"id + 1"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"s","result":"out"}}}}
    ),
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let sequences = prepare_client_local_sequences_owned(
    Pure(prepared),
    prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap(),
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    source_free_max_work=Some(100000),
    compilation_limits=Some({
      ..@publication_host.client_standard_pure_compilation_limits(),
      max_wire_bytes: 2000000,
      max_nodes: 2000000,
      max_depth: 100,
    }),
  ).unwrap()
  let mut fragments = 0
  for sequence in sequences {
    let required = @execution.generated_sequence_requirements(sequence, 100).unwrap()
    let owner = @execution.generated_sequence_owner(sequence)
    let body = @lower.bound_preparation(owner)
    for step in 0..<@lower.node_count(body) {
      if @lower.sequence_requirements_fragment_for_step(required, step)
        is Some(fragment) {
        fragments += 1
        assert_eq(fragment.measure_bytes, 100000)
        assert_eq(fragment.measure_nodes, 10000)
        assert_eq(fragment.measure_depth, 100)
      }
    }
    assert_true(@execution.generated_satisfies_requirements(sequence, required))
  }
  assert_true(fragments > 0)
}
