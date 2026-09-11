// Independent Node canonical-JSON/SHA-256 fixtures for mixed consumers.

///|
fn combined_sources(extra : Bool, joins? : Bool = false) -> @host.HostSources {
  let raw = [
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
      "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
    ),
    (
      "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515\"}",
      "sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
      "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
    ),
    (
      "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
      "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"matches_per_key\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f\"}",
      "sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a\"}",
      "sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a",
    ),
  ]
  let limits = [
    (
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624",
    ),
    (
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"subject_ref\":\"graph-input:g:edges\",\"unit\":\"edges\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af",
    ),
    (
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"matches_per_key\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f\"}],\"effective_max\":1,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:b0d2afb5e8c493abb85583a4dc707eddf983759ab92ba554b41ed12e38045e6c\",\"subject_ref\":\"sequence:checked-step:0:matches-per-key\",\"unit\":\"matches_per_key\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:b0d2afb5e8c493abb85583a4dc707eddf983759ab92ba554b41ed12e38045e6c",
    ),
    (
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a\"}],\"effective_max\":1,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:eb5a7445d7d33b6e8e88bcd37d163fc74749ab92bba86da885aa75240b7d6ae0\",\"subject_ref\":\"sequence:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
      "sha256:eb5a7445d7d33b6e8e88bcd37d163fc74749ab92bba86da885aa75240b7d6ae0",
    ),
  ]
  if extra {
    limits.push(
      (
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a\"}],\"effective_max\":1,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:e2573ff46a2f8ffd7da4efd13060ec3585201ca73a32a6393428eb777091ee8f\",\"subject_ref\":\"unused:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:e2573ff46a2f8ffd7da4efd13060ec3585201ca73a32a6393428eb777091ee8f",
      ),
    )
  }
  if joins {
    raw.push(
      (
        "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236\"}",
        "sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236",
      ),
    )
    limits.push(
      (
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236\"}],\"effective_max\":1,\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"sha256:4645c15e985a096554aab35c8fd57e5bf3b07acefb378fd6b2f4a08f3c8611fe\",\"subject_ref\":\"join:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:4645c15e985a096554aab35c8fd57e5bf3b07acefb378fd6b2f4a08f3c8611fe",
      ),
    )
  }
  let witnesses = raw.map(pair => {
    @wire.admit(@utf8.encode(pair.0), pair.1, {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap()
  })
  let mixed = @wire.check_mixed_claims(
    witnesses,
    limits.map(pair => (@utf8.encode(pair.0), pair.1)),
    {
      max_entities: 30,
      max_references: 100,
      max_bytes: 20000,
      max_nodes: 1000,
      max_depth: 10,
    },
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 30,
    max_references: 100,
  }).unwrap()
  @host.bind_claim_sources(claims, [policy(false)], {
    max_entries: 40,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 10,
  }).unwrap()
}
