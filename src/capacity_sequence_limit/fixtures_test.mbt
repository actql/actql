// Fixed fixtures independently hashed with Node SHA-256; not product output.

///|
fn policy(other : Bool) -> @policy.Policy {
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
  @policy.admit(@utf8.encode(body), id, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn fixtures(mode : Int, step : Int) -> @host.HostSources {
  let (raw, limits) = match (mode, step) {
    (0, 0) =>
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
    (1, 0) =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}",
            "sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09",
          ),
          (
            "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:286048f035401551dda405368b151deb6cd55ca20c0d79ef3e1fefc82f2f7799\"}",
            "sha256:286048f035401551dda405368b151deb6cd55ca20c0d79ef3e1fefc82f2f7799",
          ),
        ],
        [
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:2b54eda492bf98ee53e2cbc13f9aeaa6cc0daa934ba6c67e6a77aabef335f964\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:2b54eda492bf98ee53e2cbc13f9aeaa6cc0daa934ba6c67e6a77aabef335f964",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:286048f035401551dda405368b151deb6cd55ca20c0d79ef3e1fefc82f2f7799\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:c2ce16a94dae9b4e6e035a2cc0f6d3385f1b2acac7fe2cda6b2e7894020cc969\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:c2ce16a94dae9b4e6e035a2cc0f6d3385f1b2acac7fe2cda6b2e7894020cc969",
          ),
        ],
      )
    (2, 0) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:c46d7d8b90d451fe203fb1c7646f0c13311bc366516b12b3f54eb35f116fd36c\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:c46d7d8b90d451fe203fb1c7646f0c13311bc366516b12b3f54eb35f116fd36c",
          ),
        ],
      )
    (3, 0) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:6a64befa45aa8495c5c9cf1667cbd6c4f7d02000c5efd9de969bedd012de08be\",\"subject_ref\":\"sequence:checked-step:0:wrong-output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:6a64befa45aa8495c5c9cf1667cbd6c4f7d02000c5efd9de969bedd012de08be",
          ),
        ],
      )
    (4, 0) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"},{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:561ef90c5f4330dd974f167849f65ed003c30f1fb68b4fbaec526406dd34814e\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:561ef90c5f4330dd974f167849f65ed003c30f1fb68b4fbaec526406dd34814e",
          ),
        ],
      )
    (5, 0) =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:7b5eb7280471fe80ec24929c370970d3a9566b5d8cff7fa267c53480371bdf1d\"}",
            "sha256:7b5eb7280471fe80ec24929c370970d3a9566b5d8cff7fa267c53480371bdf1d",
          ),
          (
            "{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:bdf3b626b8c23ad02ac5a292bd3beb73ada4879baa116a29e4bb8bc8de60259f\"}",
            "sha256:bdf3b626b8c23ad02ac5a292bd3beb73ada4879baa116a29e4bb8bc8de60259f",
          ),
        ],
        [
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:7b5eb7280471fe80ec24929c370970d3a9566b5d8cff7fa267c53480371bdf1d\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:e6e9d9abf15280ac92b551e408b5060a92fea2a3031039f29b801d8e5eff87ad\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:e6e9d9abf15280ac92b551e408b5060a92fea2a3031039f29b801d8e5eff87ad",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:bdf3b626b8c23ad02ac5a292bd3beb73ada4879baa116a29e4bb8bc8de60259f\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:82979d0793478fa62400bd492510247acbe9251e3f88f4e858c5aa5c53d9ed19\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:82979d0793478fa62400bd492510247acbe9251e3f88f4e858c5aa5c53d9ed19",
          ),
        ],
      )
    (6, 0) =>
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
          (
            "{\"dependencies\":[\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.sequence-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_path\":\"$[0].sequence.max_output_rows\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:e052def3bb22835c68c0e06e1761d069c84d6f13631339151cffae88757dcf77\"}",
            "sha256:e052def3bb22835c68c0e06e1761d069c84d6f13631339151cffae88757dcf77",
          ),
        ],
        [
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:2b54eda492bf98ee53e2cbc13f9aeaa6cc0daa934ba6c67e6a77aabef335f964\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:2b54eda492bf98ee53e2cbc13f9aeaa6cc0daa934ba6c67e6a77aabef335f964",
          ),
          (
            "{\"author_guard_binding\":\"currently_non_binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"},{\"dependencies\":[\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.sequence-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_path\":\"$[0].sequence.max_output_rows\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:e052def3bb22835c68c0e06e1761d069c84d6f13631339151cffae88757dcf77\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:9d534a19694b3ee762220e9f30417104e68fa21e6ae22b802b30361074c14e2a\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:9d534a19694b3ee762220e9f30417104e68fa21e6ae22b802b30361074c14e2a",
          ),
        ],
      )
    (0, 1) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:06a6ecfd80f01bb381c3696547bc5410f8cd78ae19d584019bfea3e2cbb1501d\",\"subject_ref\":\"sequence:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:06a6ecfd80f01bb381c3696547bc5410f8cd78ae19d584019bfea3e2cbb1501d",
          ),
        ],
      )
    (1, 1) =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}",
            "sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09",
          ),
          (
            "{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:286048f035401551dda405368b151deb6cd55ca20c0d79ef3e1fefc82f2f7799\"}",
            "sha256:286048f035401551dda405368b151deb6cd55ca20c0d79ef3e1fefc82f2f7799",
          ),
        ],
        [
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:286048f035401551dda405368b151deb6cd55ca20c0d79ef3e1fefc82f2f7799\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:582a1b79869732ddad08110e1d142710ead2e6cbe41cacea01061f5d77abefee\",\"subject_ref\":\"sequence:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:582a1b79869732ddad08110e1d142710ead2e6cbe41cacea01061f5d77abefee",
          ),
        ],
      )
    (2, 1) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:5c464ba885c6fcdcb8e0d7034bd9abc82a82537672b334a4fb99468f498130d9\",\"subject_ref\":\"sequence:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:5c464ba885c6fcdcb8e0d7034bd9abc82a82537672b334a4fb99468f498130d9",
          ),
        ],
      )
    (3, 1) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:0d1893f3050823c598a6e8d714b700a3ec53912c85e9f79b3a02478eea9b5ddf\",\"subject_ref\":\"sequence:checked-step:1:wrong-output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:0d1893f3050823c598a6e8d714b700a3ec53912c85e9f79b3a02478eea9b5ddf",
          ),
        ],
      )
    (4, 1) =>
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
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"},{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:23e8bd264c088af10f6cdfd9a1d17d24ee72062e891d02fa7e9bfcb1d86b2fb0\",\"subject_ref\":\"sequence:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:23e8bd264c088af10f6cdfd9a1d17d24ee72062e891d02fa7e9bfcb1d86b2fb0",
          ),
        ],
      )
    (5, 1) =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:7b5eb7280471fe80ec24929c370970d3a9566b5d8cff7fa267c53480371bdf1d\"}",
            "sha256:7b5eb7280471fe80ec24929c370970d3a9566b5d8cff7fa267c53480371bdf1d",
          ),
          (
            "{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:bdf3b626b8c23ad02ac5a292bd3beb73ada4879baa116a29e4bb8bc8de60259f\"}",
            "sha256:bdf3b626b8c23ad02ac5a292bd3beb73ada4879baa116a29e4bb8bc8de60259f",
          ),
        ],
        [
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:7b5eb7280471fe80ec24929c370970d3a9566b5d8cff7fa267c53480371bdf1d\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:7bbbf86c91c165c675b8350bbd4ef6bb9ebd4ea9d3251e225ba447394889e519\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:7bbbf86c91c165c675b8350bbd4ef6bb9ebd4ea9d3251e225ba447394889e519",
          ),
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:ea17d2f959eecae149f7028103853420922c552589dc3c87250e6b3ad40f2d54\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:bdf3b626b8c23ad02ac5a292bd3beb73ada4879baa116a29e4bb8bc8de60259f\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:c3d84c19e48d72f03aaad528bc274614cd0694cba46adb9fd2a05c55d9225228\",\"subject_ref\":\"sequence:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:c3d84c19e48d72f03aaad528bc274614cd0694cba46adb9fd2a05c55d9225228",
          ),
        ],
      )
    (6, 1) =>
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
          (
            "{\"dependencies\":[\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.sequence-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_path\":\"$[0].sequence.max_output_rows\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:e052def3bb22835c68c0e06e1761d069c84d6f13631339151cffae88757dcf77\"}",
            "sha256:e052def3bb22835c68c0e06e1761d069c84d6f13631339151cffae88757dcf77",
          ),
        ],
        [
          (
            "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"matches_per_key\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cb5b3310efe6313e5e9f31738853e23f8ae6ea4bb336a205650e478116b0be09\"}],\"effective_max\":3,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d\",\"subject_ref\":\"sequence:checked-step:1:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:05dc0b1bb6b65271ee44741c7b8c6eb4015cf7a58ba2e4db89114b14e088a08d",
          ),
          (
            "{\"author_guard_binding\":\"currently_non_binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0d081c88562a566bfaabc945b51af35d62f41f02981969bd435bab72c4401ea3\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d7fa3622941cf5466aa65c73b475a9cf6e5517a30ec25f5a0e4d9b3617f9f9f1\"},{\"dependencies\":[\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.sequence-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_path\":\"$[0].sequence.max_output_rows\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:e052def3bb22835c68c0e06e1761d069c84d6f13631339151cffae88757dcf77\"}],\"effective_max\":7,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:b536994af7d076c637693da623c66c448ece227f61cdf1085eb33e275f236c90\",\"subject_ref\":\"sequence:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
            "sha256:b536994af7d076c637693da623c66c448ece227f61cdf1085eb33e275f236c90",
          ),
        ],
      )
    _ => abort("invalid fixture")
  }
  let wires = raw.map(pair => {
    @wire.admit(@utf8.encode(pair.0), pair.1, {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap()
  })
  let mixed = @wire.check_mixed_claims(
    wires,
    limits.map(pair => (@utf8.encode(pair.0), pair.1)),
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
  @host.bind_claim_sources(claims, [policy(mode == 5)], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 10,
  }).unwrap()
}
