// Independently hashed reference-format limits and source witnesses.

///|
test "Graph preflight requires mixed closure and both missing measures" {
  let p = policy(false)
  let pipeline = fixture_pipeline(true)
  let limits : @wire.ClosureLimits = { max_witnesses: 0, max_references: 0, }
  let arithmetic = @wire.check_arithmetic_claims([], limits).unwrap()
  let claims = @wire.check_program_claims(arithmetic, [], limits).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources, p, caps())
    is Err(MissingMixedClosure),
  )
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], limits).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources, p, caps())
    is Err(MissingMeasure(0, Nodes)),
  )
  assert_true(
    @capacity_graph_preflight.check_complete(
      fixture_pipeline(false),
      sources,
      p,
      { max_work: 2, max_name_bytes: 1, },
    )
    is Ok(_),
  )
}

///|
fn policy(other : Bool) -> @policy.Policy {
  let (body, id) = if other {
    (
      "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":2,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}",
      "sha256:0dc816e64973fa7621554eec60e0bf75c53e30ba709fd3bc194ad47d1c624382",
    )
  } else {
    (
      "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}",
      "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63",
    )
  }
  @policy.admit(@utf8.encode(body), id, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn sources(kind : Int, policy : @policy.Policy) -> @host.HostSources {
  let (w, l) = match (if kind == 8 { 0 } else { kind }) {
    0 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515\"}",
            "sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
          (
            "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
            "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
          ),
        ],
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
      )
    1 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f56f0dfc40a53cf8e9019fd2679692a5d521ac4a7f87f68f340af1581554cd6a\"}",
            "sha256:f56f0dfc40a53cf8e9019fd2679692a5d521ac4a7f87f68f340af1581554cd6a",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
          (
            "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
            "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
          ),
        ],
        [
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"},{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a",
          ),
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"subject_ref\":\"graph-input:g:edges\",\"unit\":\"edges\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af",
          ),
        ],
      )
    2 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515\"}",
            "sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
        ],
        [
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624",
          ),
        ],
      )
    3 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:187f4b07ef579935dce0165dd800d9460c041a2f8c6fae73dfe02a011f673b84\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:187f4b07ef579935dce0165dd800d9460c041a2f8c6fae73dfe02a011f673b84\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:187f4b07ef579935dce0165dd800d9460c041a2f8c6fae73dfe02a011f673b84\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:43ec51dbe82038bb469a29a3ed85c58e3e401db34b2da45d84b4103e10cd4f24\"}",
            "sha256:43ec51dbe82038bb469a29a3ed85c58e3e401db34b2da45d84b4103e10cd4f24",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
          (
            "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
            "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
          ),
        ],
        [
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:187f4b07ef579935dce0165dd800d9460c041a2f8c6fae73dfe02a011f673b84\",\"subject_ref\":\"graph-input:other:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:187f4b07ef579935dce0165dd800d9460c041a2f8c6fae73dfe02a011f673b84",
          ),
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"subject_ref\":\"graph-input:g:edges\",\"unit\":\"edges\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af",
          ),
        ],
      )
    4 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:dac76a060d43e8b61f42a88d83d5cbe2a86eefbe38237ef23fb94527976e1a58\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:dac76a060d43e8b61f42a88d83d5cbe2a86eefbe38237ef23fb94527976e1a58\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:dac76a060d43e8b61f42a88d83d5cbe2a86eefbe38237ef23fb94527976e1a58\",\"semantic_ref\":\"ghost\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:100c87b708966b1ffd1adc035a9c8c160da17549f3355b5783dd94b830b7ed40\"}",
            "sha256:100c87b708966b1ffd1adc035a9c8c160da17549f3355b5783dd94b830b7ed40",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
          (
            "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
            "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
          ),
        ],
        [
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:dac76a060d43e8b61f42a88d83d5cbe2a86eefbe38237ef23fb94527976e1a58\",\"subject_ref\":\"graph-input:ghost:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:dac76a060d43e8b61f42a88d83d5cbe2a86eefbe38237ef23fb94527976e1a58",
          ),
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"subject_ref\":\"graph-input:g:edges\",\"unit\":\"edges\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af",
          ),
        ],
      )
    5 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515\"}",
            "sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
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
            "{\"dependencies\":[\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f56f0dfc40a53cf8e9019fd2679692a5d521ac4a7f87f68f340af1581554cd6a\"}",
            "sha256:f56f0dfc40a53cf8e9019fd2679692a5d521ac4a7f87f68f340af1581554cd6a",
          ),
        ],
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
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"},{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:65a7412e9444f58a05bd41657233a851f5dbac5ce5a6dc81cfd18bc2aee59c8a",
          ),
        ],
      )
    6 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:6b1492aa44879af1f63999a498979c4b786dd27b1e5ce0bd55d3a051a80ae865\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:6b1492aa44879af1f63999a498979c4b786dd27b1e5ce0bd55d3a051a80ae865\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:6b1492aa44879af1f63999a498979c4b786dd27b1e5ce0bd55d3a051a80ae865\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:14a73af445a804a276d4e7d5d7d576694ebd272cf8c7161c39f1ae741d0d90ee\"}",
            "sha256:14a73af445a804a276d4e7d5d7d576694ebd272cf8c7161c39f1ae741d0d90ee",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
          (
            "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.components-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.inputs.g.guard\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ba3b7e574a4e5a823ad342d6fbe3c5d73eab1d97408b390c320ce13e3423f72f\"}",
            "sha256:ba3b7e574a4e5a823ad342d6fbe3c5d73eab1d97408b390c320ce13e3423f72f",
          ),
          (
            "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
            "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
          ),
        ],
        [
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"currently_non_binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.components-output\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.inputs.g.guard\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ba3b7e574a4e5a823ad342d6fbe3c5d73eab1d97408b390c320ce13e3423f72f\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:6b1492aa44879af1f63999a498979c4b786dd27b1e5ce0bd55d3a051a80ae865\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:6b1492aa44879af1f63999a498979c4b786dd27b1e5ce0bd55d3a051a80ae865",
          ),
          (
            @utf8.encode(
              "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"subject_ref\":\"graph-input:g:edges\",\"unit\":\"edges\",\"version\":\"actql-resolved-limit/0.1\"}",
            ),
            "sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af",
          ),
        ],
      )
    7 =>
      (
        [
          (
            "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:2b0c8469a7ac6df1d44306088973f0efc53965b5acb1ea9ba15fd94554913449\"}",
            "sha256:2b0c8469a7ac6df1d44306088973f0efc53965b5acb1ea9ba15fd94554913449",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
            "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
          ),
          (
            "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
            "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
          ),
          (
            "{\"dependencies\":[\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\"},\"law_id\":\"actql.bound.graph-input-edges\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:9413cd95b9f98a6e03262f000b4faabc3e02658503ce389d1584cd7c404483af\",\"semantic_ref\":\"g\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30\"}",
            "sha256:45c7607e7e1492889812bede88ec33270760ab62117eeab48ff84c84b9e5df30",
          ),
        ],
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
      )
    _ => abort("unknown fixture")
  }
  let wires = w.map(pair => {
    @wire.admit(@utf8.encode(pair.0), pair.1, {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 5,
    }).unwrap()
  })
  // Keep the valid limits and Host sources, but no enforced consumer claims.
  let wires = if kind == 8 {
    wires.filter(w => @wire.role(w) == @arithmetic.HostCeiling)
  } else {
    wires
  }
  let mixed = @wire.check_mixed_claims(wires, l, {
    max_entities: 30,
    max_references: 100,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 6,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 30,
    max_references: 100,
  }).unwrap()
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 5,
  }).unwrap()
}

///|
fn fixture_pipeline(
  graph : Bool,
  opaque_graph? : Bool = false,
  extra? : Bool = false,
) -> @pipeline.CheckedPipeline {
  let source = @decode.admit(
    @source.parse_json("[]", { max_input_bytes: 2, max_nodes: 1, max_depth: 1, }).unwrap(),
    {
      max_nodes: 1,
      max_depth: 1,
      max_string_bytes: 0,
      max_total_string_bytes: 0,
    },
  ).unwrap()
  let carrier = if graph {
    @carrier.graph(
      @contract.primitive(StringType, nullable=false),
      @carrier.unknown_rows(),
      @carrier.unknown_rows(),
      labels=None,
      max_labels=0,
      max_label_bytes=0,
    ).unwrap()
  } else {
    @carrier.relation(@carrier.unknown_rows())
  }
  let carrier = if opaque_graph {
    @carrier.unknown_carrier(GraphKind)
  } else {
    carrier
  }
  let inputs = [("g", carrier)]
  if extra {
    inputs.push(("unused", @carrier.unknown_carrier(GraphKind)))
  }
  let from = @decode.admit(
    @source.parse_json("\"g\"", {
      max_input_bytes: 3,
      max_nodes: 1,
      max_depth: 0,
    }).unwrap(),
    {
      max_nodes: 1,
      max_depth: 0,
      max_string_bytes: 1,
      max_total_string_bytes: 1,
    },
  ).unwrap()
  @pipeline.check_carriers(source, inputs, None, Some(from), {
    max_steps: 0,
    max_work: 100,
    max_text_bytes: 100,
    max_nodes: 100,
    max_tokens: 100,
    max_depth: 10,
  }).unwrap()
}

///|
fn caps() -> @capacity_graph_preflight.Limits {
  { max_work: 100, max_name_bytes: 100, }
}

///|
test "Graph preflight binds selected policy and complete input measures" {
  let p = policy(false)
  let pipeline = fixture_pipeline(true)
  for kind in [0, 1] {
    let sources = sources(kind, p)
    let bound = @capacity_graph_preflight.check(pipeline, sources, p, caps()).unwrap()
    assert_eq(@capacity_graph_preflight.unconsumed_limit_count(bound), 0)
    assert_true(
      @capacity_graph_preflight.check_complete(pipeline, sources, p, caps())
      is Ok(_),
    )
    assert_true(
      physical_equal(
        @capacity_graph_preflight.checked_pipeline(bound),
        pipeline,
      ),
    )
    assert_true(
      physical_equal(@capacity_graph_preflight.checked_sources(bound), sources),
    )
    assert_true(
      physical_equal(@capacity_graph_preflight.selected_policy(bound), p),
    )
    for
      measure in [
        @capacity_graph_preflight.Measure::Nodes,
        @capacity_graph_preflight.Measure::Edges,
      ] {
      let limit = @capacity_graph_preflight.input_limit(bound, 0, measure).unwrap()
      assert_eq(@arithmetic.minimum_value(@wire.limit_minimum(limit)), 1L)
    }
    assert_true(@capacity_graph_preflight.input_limit(bound, -1, Nodes) is None)
    assert_true(@capacity_graph_preflight.input_limit(bound, 1, Edges) is None)
    let (work, names) = @capacity_graph_preflight.usage(bound)
    assert_eq(names, 1)
    assert_true(
      @capacity_graph_preflight.check_complete(pipeline, sources, p, {
        max_work: work,
        max_name_bytes: names,
      })
      is Ok(_),
    )
    assert_true(
      @capacity_graph_preflight.check(pipeline, sources, p, {
        max_work: work - 1,
        max_name_bytes: names,
      })
      is Err(BudgetExceeded),
    )
    assert_true(
      @capacity_graph_preflight.check(pipeline, sources, p, {
        max_work: work,
        max_name_bytes: 0,
      })
      is Err(BudgetExceeded),
    )
  }
  assert_eq(@pipeline.input_count(pipeline), 1)
  assert_true(@pipeline.input_at(pipeline, -1) is None)
  assert_true(@pipeline.input_at(pipeline, 1) is None)
}

///|
test "Graph preflight rejects wrong targets incomplete measures and foreign scopes" {
  let p = policy(false)
  let pipeline = fixture_pipeline(true)
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources(2, p), p, caps())
    is Err(MissingMeasure(0, Edges)),
  )
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources(3, p), p, caps())
    is Err(SubjectMismatch(_)),
  )
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources(4, p), p, caps())
    is Err(UnknownInput("ghost")),
  )
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources(5, p), p, caps())
    is Err(DuplicateMeasure(0, Nodes)),
  )
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources(6, p), p, caps())
    is Err(UnsupportedCandidate(_, _)),
  )
  assert_true(
    @capacity_graph_preflight.check(pipeline, sources(7, p), p, caps())
    is Err(UnsupportedEnforcedLaw(_)),
  )
  assert_true(
    @capacity_graph_preflight.check(
      fixture_pipeline(false),
      sources(0, p),
      p,
      caps(),
    )
    is Err(WrongCarrier("g")),
  )
  assert_true(
    @capacity_graph_preflight.check(
      pipeline,
      sources(0, p),
      policy(true),
      caps(),
    )
    is Err(CandidateScopeMismatch(_, _)),
  )
}

///|
test "Graph preflight covers opaque and unused Graph inputs" {
  let p = policy(false)
  let input = fixture_pipeline(true, opaque_graph=true)
  assert_true(
    @capacity_graph_preflight.check(input, sources(0, p), p, caps()) is Ok(_),
  )
  assert_true(
    @capacity_graph_preflight.check(input, sources(2, p), p, caps())
    is Err(MissingMeasure(0, Edges)),
  )
  assert_true(
    @capacity_graph_preflight.check(
      fixture_pipeline(true, extra=true),
      sources(0, p),
      p,
      caps(),
    )
    is Err(MissingMeasure(1, Nodes)),
  )
  assert_true(
    @capacity_graph_preflight.check(input, sources(0, p), p, {
      max_work: -1,
      max_name_bytes: 100,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    @capacity_graph_preflight.check(input, sources(0, p), p, {
      max_work: 100,
      max_name_bytes: -1,
    })
    is Err(InvalidLimits),
  )
}
