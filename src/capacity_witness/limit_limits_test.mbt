///|
test "limit admission enforces complete artifact node and depth budgets" {
  let claims = limit_graph()
  for
    (body, id, nodes, depth, mode) in [
      (
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":10,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:2ad0db850eeb11db2b6312420de6d985065dd6dcb028d43209726910e27db6df\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:2ad0db850eeb11db2b6312420de6d985065dd6dcb028d43209726910e27db6df",
        25,
        4,
        Enforcement::Static,
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:806e2c34f91793d12507aab0b8a23e0380180f262f69b96fdc8bace65aabcae0\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:806e2c34f91793d12507aab0b8a23e0380180f262f69b96fdc8bace65aabcae0",
        40,
        4,
        Enforcement::UnitPreflight,
      ),
      (
        "{\"author_guard_binding\":\"currently_non_binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:939ff64725a7ddcd1ee5e2f7b8ab492ae806137718072855023b2390ce53faf1\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":10,\"enforcement\":\"before_provider_dispatch\",\"resolved_limit_cid\":\"sha256:6a4ebfebbb80ffb92b4ad3ead9779af7416b585914d31fb14b9f954f915b6e68\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:6a4ebfebbb80ffb92b4ad3ead9779af7416b585914d31fb14b9f954f915b6e68",
        40,
        4,
        Enforcement::BeforeProviderDispatch,
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"before_effect_commit\",\"resolved_limit_cid\":\"sha256:7e39a0b92ed6043755508114fc8c72daacd6e908edb28d5ddb2429864dfa8c09\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:7e39a0b92ed6043755508114fc8c72daacd6e908edb28d5ddb2429864dfa8c09",
        25,
        4,
        Enforcement::BeforeEffectCommit,
      ),
      (
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":10,\"enforcement\":\"streaming_atomic\",\"resolved_limit_cid\":\"sha256:d0268b1717560d64d79fe4c1c63ff5de40692438fa7e90fee637bdd3c36ff0f1\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:d0268b1717560d64d79fe4c1c63ff5de40692438fa7e90fee637bdd3c36ff0f1",
        40,
        4,
        Enforcement::StreamingAtomic,
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:5de5907e11d6f7682aed62a0ea280176715a1388baacff036ad6d41bb36087ee\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:5de5907e11d6f7682aed62a0ea280176715a1388baacff036ad6d41bb36087ee",
        55,
        4,
        Enforcement::EngineAtomic,
      ),
    ] {
    let bytes = @utf8.encode(body)
    let caps = { ..limit_caps(), max_nodes: nodes, max_depth: depth, }
    assert_eq(
      limit_enforcement(admit_limit(bytes, id, claims, caps).unwrap()),
      mode,
    )
    assert_eq(
      admit_limit(bytes, id, claims, { ..caps, max_nodes: nodes - 1, }).unwrap_err(),
      BudgetExceeded,
    )
    assert_eq(
      admit_limit(bytes, id, claims, { ..caps, max_depth: depth - 1, }).unwrap_err(),
      BudgetExceeded,
    )
    let invalid : Array[LimitLimits] = [
      { ..caps, max_bytes: -1, },
      { ..caps, max_nodes: -1, },
      { ..caps, max_depth: -1, },
      { ..caps, max_candidates: -1, },
    ]
    for limits in invalid {
      assert_eq(
        admit_limit(bytes, id, claims, limits).unwrap_err(),
        InvalidLimits,
      )
    }
  }
}
