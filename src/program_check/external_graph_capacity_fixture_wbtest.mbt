///|
// Reuse independently pinned Graph preflight inputs and the SourceView corpus.
// This fixture supplies input enforcement, not derived operation proofs.
fn external_graph_capacity_fixture() -> (
  @environment.WireEnvironment,
  @host.HostSources,
) {
  let environment = @environment.read(
    @utf8.encode(
      "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:27f2b81b9a3ac189b23fe1c0202d62264c8226c2e7876cfb8593380eee5de7a2\",\"commands\":[],\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contracts\":[{\"body\":{\"edge_labels\":null,\"edge_properties\":{},\"identity_law_cid\":\"sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4\",\"node_id_contract\":{\"nullable\":false,\"type\":\"number\"},\"node_properties\":{},\"value_law_cid\":\"sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4\",\"version\":\"actql-graph-contract/0.1\"},\"cid\":\"sha256:73b892198e71b01c9f7438218b32556e69b5905512790d34d8a7717a1d2985a0\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:555fa1b8ce51a6778d8ce7061b4c0aab06509c282fa7db518ea8e336f8327cb4\",\"output\":{\"carrier\":\"graph\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:73b892198e71b01c9f7438218b32556e69b5905512790d34d8a7717a1d2985a0\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}]}],\"contract_registry\":[{\"body\":{\"edge_labels\":null,\"edge_properties\":{},\"identity_law_cid\":\"sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4\",\"node_id_contract\":{\"nullable\":false,\"type\":\"number\"},\"node_properties\":{},\"value_law_cid\":\"sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4\",\"version\":\"actql-graph-contract/0.1\"},\"cid\":\"sha256:73b892198e71b01c9f7438218b32556e69b5905512790d34d8a7717a1d2985a0\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"evidence_bundle_cid\":\"sha256:09bdd500a960657b8cacaa174cc449364ce5b718882e59c34f05e16e22b7d8f6\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:555fa1b8ce51a6778d8ce7061b4c0aab06509c282fa7db518ea8e336f8327cb4\",\"output\":{\"carrier\":\"graph\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:73b892198e71b01c9f7438218b32556e69b5905512790d34d8a7717a1d2985a0\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}],\"version\":\"actql-check-environment/0.1\"}",
    ),
    "sha256:09bdd500a960657b8cacaa174cc449364ce5b718882e59c34f05e16e22b7d8f6",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 1000, },
  ).unwrap()
  let policy = @policy.admit(
    @utf8.encode(
      "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}",
    ),
    "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let witnesses = [
    @wire.admit(
      @utf8.encode(
        "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515\"}",
      ),
      "sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515",
      limits,
    ).unwrap(),
    @wire.admit(
      @utf8.encode(
        "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
      ),
      "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
      limits,
    ).unwrap(),
    @wire.admit(
      @utf8.encode(
        "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
      ),
      "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
      limits,
    ).unwrap(),
    @wire.admit(
      @utf8.encode(
        "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
      ),
      "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
      limits,
    ).unwrap(),
  ]
  let mixed = @wire.check_mixed_claims(
    witnesses,
    [
      (
        @utf8.encode(
          "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
        ),
        "sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624",
      ),
      (
        @utf8.encode(
          "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"subject_ref\":\"graph-input:g:edges\",\"unit\":\"edges\",\"version\":\"actql-resolved-limit/0.1\"}",
        ),
        "sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af",
      ),
    ],
    {
      max_entities: 100,
      max_references: 1000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 100,
    max_references: 1000,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  (environment, sources)
}
