// Fixed bytes and identities calculated independently with Node SHA-256.
// These synthetic claims test integrity, not source-law applicability.

///|
fn limit_graph() -> ArithmeticClaims {
  let witnesses = [
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}",
      "sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}",
      "sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:939ff64725a7ddcd1ee5e2f7b8ab492ae806137718072855023b2390ce53faf1\"}",
      "sha256:939ff64725a7ddcd1ee5e2f7b8ab492ae806137718072855023b2390ce53faf1",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"bytes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:5ada0d8a4950d707fbae104e63609c487782dc6799018b3cdf09ab04afdf2895\"}",
      "sha256:5ada0d8a4950d707fbae104e63609c487782dc6799018b3cdf09ab04afdf2895",
    ),
  ]
  check_arithmetic_claims(witnesses, { max_witnesses: 4, max_references: 4, }).unwrap()
}

///|
fn limit_caps() -> LimitLimits {
  { max_bytes: 10000, max_nodes: 200, max_depth: 10, max_candidates: 10, }
}

///|
test "canonical limit claims retain candidate occurrences and recomputed minima" {
  let claims = limit_graph()
  let cases = [
    (
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":10,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:2ad0db850eeb11db2b6312420de6d985065dd6dcb028d43209726910e27db6df\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:2ad0db850eeb11db2b6312420de6d985065dd6dcb028d43209726910e27db6df",
      10L,
      1,
      @arithmetic.GuardBinding::Absent,
    ),
    (
      "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:806e2c34f91793d12507aab0b8a23e0380180f262f69b96fdc8bace65aabcae0\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:806e2c34f91793d12507aab0b8a23e0380180f262f69b96fdc8bace65aabcae0",
      5L,
      2,
      @arithmetic.GuardBinding::Binding,
    ),
    (
      "{\"author_guard_binding\":\"currently_non_binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:939ff64725a7ddcd1ee5e2f7b8ab492ae806137718072855023b2390ce53faf1\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":10,\"enforcement\":\"before_provider_dispatch\",\"resolved_limit_cid\":\"sha256:6a4ebfebbb80ffb92b4ad3ead9779af7416b585914d31fb14b9f954f915b6e68\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:6a4ebfebbb80ffb92b4ad3ead9779af7416b585914d31fb14b9f954f915b6e68",
      10L,
      2,
      @arithmetic.GuardBinding::CurrentlyNonBinding,
    ),
    (
      "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"before_effect_commit\",\"resolved_limit_cid\":\"sha256:7e39a0b92ed6043755508114fc8c72daacd6e908edb28d5ddb2429864dfa8c09\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:7e39a0b92ed6043755508114fc8c72daacd6e908edb28d5ddb2429864dfa8c09",
      5L,
      1,
      @arithmetic.GuardBinding::Binding,
    ),
    (
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":10,\"enforcement\":\"streaming_atomic\",\"resolved_limit_cid\":\"sha256:d0268b1717560d64d79fe4c1c63ff5de40692438fa7e90fee637bdd3c36ff0f1\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:d0268b1717560d64d79fe4c1c63ff5de40692438fa7e90fee637bdd3c36ff0f1",
      10L,
      2,
      @arithmetic.GuardBinding::Absent,
    ),
    (
      "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:5de5907e11d6f7682aed62a0ea280176715a1388baacff036ad6d41bb36087ee\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:5de5907e11d6f7682aed62a0ea280176715a1388baacff036ad6d41bb36087ee",
      5L,
      3,
      @arithmetic.GuardBinding::Binding,
    ),
  ]
  for (body, id, maximum, n, binding) in cases {
    let bytes = @utf8.encode(body)
    let v = admit_limit(bytes, id, claims, limit_caps()).unwrap()
    assert_true(physical_equal(limit_claims(v), claims))
    assert_eq(limit_cid(v), id)
    assert_eq(limit_subject(v), "stage.s.output")
    let writer = @encode.writer(10000, 200, 10)
    emit_limit(v, writer)
    assert_eq(@encode.finish(writer), body)
    assert_eq(@arithmetic.minimum_value(limit_minimum(v)), maximum)
    assert_eq(@arithmetic.minimum_guard_binding(limit_minimum(v)), binding)
    assert_eq(@arithmetic.minimum_candidate_count(limit_minimum(v)), n)
    let exact = {
      ..limit_caps(),
      max_bytes: bytes.length(),
      max_candidates: n,
    }
    assert_true(admit_limit(bytes, id, claims, exact) is Ok(_))
    assert_eq(
      admit_limit(bytes, id, claims, { ..exact, max_bytes: bytes.length() - 1, }).unwrap_err(),
      BudgetExceeded,
    )
    assert_eq(
      admit_limit(bytes, id, claims, { ..exact, max_candidates: n - 1, }).unwrap_err(),
      BudgetExceeded,
    )
    assert_eq(
      admit_limit(@utf8.encode(" " + body), id, claims, limit_caps()).unwrap_err(),
      NoncanonicalArtifact,
    )
    assert_eq(
      admit_limit(bytes, "sha256:" + "0".repeat(64), claims, limit_caps()).unwrap_err(),
      IdentityMismatch,
    )
    let empty = check_arithmetic_claims([], {
      max_witnesses: 0,
      max_references: 0,
    }).unwrap()
    assert_eq(
      admit_limit(bytes, id, empty, limit_caps()).unwrap_err(),
      InvalidWitness,
    )
  }
}

///|
test "self-consistent limit hashes cannot hide invalid claims or repaired bodies" {
  let claims = limit_graph()
  for
    (body, id) in [
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":4,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:cd2bf7ff82095b7573529e96e8ee6bbebfa4472874eb7f3b92b33093bd9f1acc\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:cd2bf7ff82095b7573529e96e8ee6bbebfa4472874eb7f3b92b33093bd9f1acc",
      ),
      (
        "{\"author_guard_binding\":\"currently_non_binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:34b455067393a6602b35a200bcd6d6f4838bbf50dac0e3578795e88ceaec5898\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:34b455067393a6602b35a200bcd6d6f4838bbf50dac0e3578795e88ceaec5898",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:5a635679bbdd1a9909a7e2d6bee1d031368b4f3be5deda34b6e9d762877314f4\",\"subject_ref\":\"stage.s.output\",\"unit\":\"bytes\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:5a635679bbdd1a9909a7e2d6bee1d031368b4f3be5deda34b6e9d762877314f4",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:bafbc39aa6a7ca315d92a1f1fd389833cf0829c14dd2ece6ff46927e3995c734\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:bafbc39aa6a7ca315d92a1f1fd389833cf0829c14dd2ece6ff46927e3995c734",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"truncate\",\"resolved_limit_cid\":\"sha256:0f5b0f8d219c97669e7fe7c813618b8e9cdf385451c78e9d67ec0eadb192ceb6\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:0f5b0f8d219c97669e7fe7c813618b8e9cdf385451c78e9d67ec0eadb192ceb6",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"skip\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:5380eb51b56a24ae7fe2b50a2c5e7aa4f39a5d7446cd11c4beba816b66ae7c92\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:5380eb51b56a24ae7fe2b50a2c5e7aa4f39a5d7446cd11c4beba816b66ae7c92",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:95a6e39d15466379114b1417646ad0bcf778702e3f7681da18ba3dc6d79c7681\",\"subject_ref\":\"\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:95a6e39d15466379114b1417646ad0bcf778702e3f7681da18ba3dc6d79c7681",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"extra\":1,\"resolved_limit_cid\":\"sha256:37b5ec24fa272cec1c163d975b23bca672c2d5380f5dd64c64acd259dc01b207\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:37b5ec24fa272cec1c163d975b23bca672c2d5380f5dd64c64acd259dc01b207",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:17d5187cd29cc430e835a80ee13a1e1c8ea178a419bd2beb0cfd18c64eccf6e2\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:17d5187cd29cc430e835a80ee13a1e1c8ea178a419bd2beb0cfd18c64eccf6e2",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:250359751e0915b2314464c02a0bbc3582a5ec7df07c04c57b07b4a67e7e1ffb\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:250359751e0915b2314464c02a0bbc3582a5ec7df07c04c57b07b4a67e7e1ffb",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":9,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:68d0c99bc92f1b72722a530da76e1c58a48a0c237fc4bcb0850cd438661be3d4\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:68d0c99bc92f1b72722a530da76e1c58a48a0c237fc4bcb0850cd438661be3d4",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"extra\":{\"deep\":[1,2,3]},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ca296c391c5862917005095a829bfb4190135299746162feb97c112217ecfe2d\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.steps[0].max_output_rows\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ee0f8ecac1e3f78846c2ce0650e1df4e08dc72420a62f14e6a4edac3b28edca2\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:5b84f631066b3f98e28ccb912c1c91606b98c5d5668af6e2e758b7288136ea1f\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:5b84f631066b3f98e28ccb912c1c91606b98c5d5668af6e2e758b7288136ea1f",
      ),
      (
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"bytes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:5ada0d8a4950d707fbae104e63609c487782dc6799018b3cdf09ab04afdf2895\"}],\"effective_max\":5,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:8f03d09060ea83efdff92cee18f0e15bb53005aea6aea7dcbbe0fa89664ab023\",\"subject_ref\":\"stage.s.output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:8f03d09060ea83efdff92cee18f0e15bb53005aea6aea7dcbbe0fa89664ab023",
      ),
    ] {
    assert_true(
      admit_limit(@utf8.encode(body), id, claims, limit_caps()) is Err(_),
    )
  }
}
