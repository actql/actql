///|
fn sequence_limit_policy(other : Bool) -> @policy.Policy {
  let (body, id) = if other {
    (
      "{\"max_aggregate_array_items\":7,\"max_artifact_bytes\":7,\"max_artifact_rows\":7,\"max_effect_items\":7,\"max_graph_input_edges\":7,\"max_graph_input_nodes\":7,\"max_graph_output_rows\":7,\"max_graph_paths\":7,\"max_infer_items\":7,\"max_model_input_tokens_per_item\":7,\"max_model_request_bytes_per_item\":7,\"max_model_total_duration_ms\":7,\"max_nested_value_bytes\":7,\"max_nested_value_depth\":8,\"max_relation_output_rows\":7,\"max_temporal_matches_per_key\":3,\"max_temporal_output_rows\":7,\"version\":\"actql-capacity-host-policy/0.1\"}",
      "sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54",
    )
  } else {
    (
      "{\"max_aggregate_array_items\":7,\"max_artifact_bytes\":7,\"max_artifact_rows\":7,\"max_effect_items\":7,\"max_graph_input_edges\":7,\"max_graph_input_nodes\":7,\"max_graph_output_rows\":7,\"max_graph_paths\":7,\"max_infer_items\":7,\"max_model_input_tokens_per_item\":7,\"max_model_request_bytes_per_item\":7,\"max_model_total_duration_ms\":7,\"max_nested_value_bytes\":7,\"max_nested_value_depth\":7,\"max_relation_output_rows\":7,\"max_temporal_matches_per_key\":3,\"max_temporal_output_rows\":7,\"version\":\"actql-capacity-host-policy/0.1\"}",
      "sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3",
    )
  }
  @policy.admit(@wire_utf8.encode(body), id, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn sequence_limit_raw() -> (Array[(String, String)], Array[(String, String)]) {
  (
    [
      (
        "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}",
        "sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09",
      ),
      (
        "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}",
        "sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1",
      ),
    ],
    [
      (
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:2b54eda492bf98ee53e2cbc13f9aeaa6cc0daa934ba6c67e6a77aabef335f964\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:2b54eda492bf98ee53e2cbc13f9aeaa6cc0daa934ba6c67e6a77aabef335f964",
      ),
      (
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:7ce07e358c7f9671d7df04ed151f49c3a8279e55169c19b19e96f3066dbc9e6b\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:7ce07e358c7f9671d7df04ed151f49c3a8279e55169c19b19e96f3066dbc9e6b",
      ),
    ],
  )
}

///|
fn sequence_limit_sources() -> @host.HostSources {
  let raw : Array[(String, String)] = []
  let limits : Array[(String, String)] = []
  let seen : Map[String, Bool] = Map([])
  for _ in [0] {
    let (witnesses, scope_limits) = sequence_limit_raw()
    for pair in witnesses {
      if !seen.contains(pair.1) {
        seen[pair.1] = true
        raw.push(pair)
      }
    }
    for limit in scope_limits {
      limits.push(limit)
    }
  }
  let wires = raw.map(pair => {
    @wire.admit(@wire_utf8.encode(pair.0), pair.1, {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap()
  })
  let mixed = @wire.check_mixed_claims(
    wires,
    limits.map(pair => (@wire_utf8.encode(pair.0), pair.1)),
    {
      max_entities: 20,
      max_references: 100,
      max_bytes: 20000,
      max_nodes: 1000,
      max_depth: 10,
    },
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 20,
    max_references: 100,
  }).unwrap()
  @host.bind_claim_sources(claims, [sequence_limit_policy(false)], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 10,
  }).unwrap()
}
