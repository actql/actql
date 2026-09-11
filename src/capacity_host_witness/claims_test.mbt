// Fixed corpus bodies and independently generated Node limit/preflight fixtures.

///|
fn source_wires() -> Array[@wire.WireWitness] {
  [
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.aggregate-array-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_aggregate_array_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"array_items\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4c7ae8cb395c5ec84af3eb3d0cf4ff7f9a893c10485c47e99fc82318904da156\"}",
      "sha256:4c7ae8cb395c5ec84af3eb3d0cf4ff7f9a893c10485c47e99fc82318904da156",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.artifact-bytes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_artifact_bytes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"bytes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4e239a9b0fb7df0afa291d763125f3e82ae0495f6bed6b8ed4c8dad74d38d6c1\"}",
      "sha256:4e239a9b0fb7df0afa291d763125f3e82ae0495f6bed6b8ed4c8dad74d38d6c1",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.artifact-rows\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_artifact_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:0e2535b7ccbbbd1d573be32f28ad6a864d3d52563c4b766ab00ad0729462a4f5\"}",
      "sha256:0e2535b7ccbbbd1d573be32f28ad6a864d3d52563c4b766ab00ad0729462a4f5",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.effect-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_effect_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"effect_items\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a223a89ae11d24c9be60416dd5c35be6bdb2c01aed0705b4a83089fe87574e31\"}",
      "sha256:a223a89ae11d24c9be60416dd5c35be6bdb2c01aed0705b4a83089fe87574e31",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-edges\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_edges\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"edges\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081\"}",
      "sha256:d8f268c74bf29b8a5ed90cb9b3cbee761e214dc3533e51dccbbbba5f673c0081",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}",
      "sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:5f824a9498c4e9db05c8024e88f85fc829a962cce0a96a07672ee9587323d317\"}",
      "sha256:5f824a9498c4e9db05c8024e88f85fc829a962cce0a96a07672ee9587323d317",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-paths\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_paths\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"paths\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:50d83be0393ba0390442d3a7e13d0b6242c18f61f4bc6d2a5ad510a132fe0663\"}",
      "sha256:50d83be0393ba0390442d3a7e13d0b6242c18f61f4bc6d2a5ad510a132fe0663",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.infer-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_infer_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"distinct_keys\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f632cb199d47a451c8941ab0efc540d193d41515c95b4fbedc6a6f74d9f096cb\"}",
      "sha256:f632cb199d47a451c8941ab0efc540d193d41515c95b4fbedc6a6f74d9f096cb",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.model-request-bytes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_model_request_bytes_per_item\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"bytes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d58381703b0186b1c307070cd79c5732c3939a48639e13d117c91cfdca1333de\"}",
      "sha256:d58381703b0186b1c307070cd79c5732c3939a48639e13d117c91cfdca1333de",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.nested-value-bytes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_nested_value_bytes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"bytes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:b829c499a1f241813e7e31dd5a884d5fee4dcdfd9fc79e89bedb6d8827220688\"}",
      "sha256:b829c499a1f241813e7e31dd5a884d5fee4dcdfd9fc79e89bedb6d8827220688",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.relation-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_relation_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236\"}",
      "sha256:cc804f91bfb333cce941d90ede1e71d04e829b342464a24e88f237db814f4236",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-matches\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_matches_per_key\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"matches_per_key\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f\"}",
      "sha256:1b3618e1b620afedd28431b4805864fdc6545e3b68563faafa327b8fe199c85f",
    ),
    (
      "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.temporal-output\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_temporal_output_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a\"}",
      "sha256:3f1a4583295af001e484a445f0e59eee53fca34e5704f8e5affadb02a2cc230a",
    ),
    (
      "{\"dependencies\":[\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515\"}",
      "sha256:1f94fcc4d981bce49ad8f3fe3e585985772fdacd27c11986bd4da24bfa27e515",
    ),
  ].map(pair => {
    @wire.admit(@utf8.encode(pair.0), pair.1, {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 4,
    }).unwrap()
  })
}

///|
fn source_program(w : Array[@wire.WireWitness]) -> @wire.ProgramClaims {
  let mixed = @wire.check_mixed_claims(
    w,
    [
      (
        @utf8.encode(
          "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:728fa5aab0a06fecedd20ce698143c5dc48e1a5db43d95f0aa0bf2be222840eb\"}],\"effective_max\":1,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
        ),
        "sha256:3bb96fa2c56847edb6190cb6ccc68a63bd5c3c75f5604c71bc918a5c4949c624",
      ),
    ],
    {
      max_entities: 30,
      max_references: 100,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 5,
    },
  ).unwrap()
  @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 30,
    max_references: 100,
  }).unwrap()
}

///|
fn binding_caps() -> @capacity_host_witness.BindingLimits {
  { max_entries: 30, max_bytes: 20000, max_nodes: 1000, max_depth: 5, }
}

///|
test "Host source binding validates every field and retains mixed proof ownership" {
  let p = policy(fixture())
  let policies = [p]
  let claims = source_program(source_wires())
  let bound = @capacity_host_witness.bind_claim_sources(
    claims,
    policies,
    binding_caps(),
  ).unwrap()
  assert_true(
    physical_equal(@capacity_host_witness.source_claims(bound), claims),
  )
  assert_eq(@capacity_host_witness.source_count(bound), 14)
  for
    i, field in [
      "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
      "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows",
      "max_graph_paths", "max_infer_items", "max_model_request_bytes_per_item", "max_nested_value_bytes",
      "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
    ] {
    let source = @capacity_host_witness.source_at(bound, i).unwrap()
    assert_eq(
      @policy.ceiling_field(@capacity_host_witness.ceiling(source)),
      field,
    )
    assert_true(
      physical_equal(
        @policy.ceiling_policy(@capacity_host_witness.ceiling(source)),
        p,
      ),
    )
  }
  assert_true(@capacity_host_witness.source_at(bound, 14) is None)
  assert_true(@capacity_host_witness.source_at(bound, -1) is None)
  assert_true(@capacity_host_witness.source_at(bound, 15) is None)
  assert_true(
    @wire.program_claim_mixed(@capacity_host_witness.source_claims(bound))
    is Some(_),
  )
  let (bytes, nodes) = @capacity_host_witness.source_usage(bound)
  let exact = {
    ..binding_caps(),
    max_entries: 16,
    max_bytes: bytes,
    max_nodes: nodes,
  }
  assert_true(
    @capacity_host_witness.bind_claim_sources(claims, policies, exact) is Ok(_),
  )
  let lows : Array[@capacity_host_witness.BindingLimits] = [
    { ..exact, max_entries: 15, },
    { ..exact, max_bytes: bytes - 1, },
    { ..exact, max_nodes: nodes - 1, },
    { ..exact, max_depth: 1, },
  ]
  for cap in lows {
    assert_true(
      @capacity_host_witness.bind_claim_sources(claims, policies, cap)
      is Err(BindingBudgetExceeded),
    )
  }
  policies.clear()
  assert_eq(@capacity_host_witness.source_count(bound), 14)
}

///|
test "Host source binding rejects missing duplicate and unused invalid sources" {
  let p = policy(fixture())
  let claims = source_program(source_wires())
  assert_true(
    @capacity_host_witness.bind_claim_sources(claims, [], binding_caps())
    is Err(MissingPolicy(0, _)),
  )
  assert_true(
    @capacity_host_witness.bind_claim_sources(claims, [p, p], binding_caps())
    is Err(DuplicatePolicy(_)),
  )
  let other = policy(
    "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":2,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}",
  )
  assert_true(
    @capacity_host_witness.bind_claim_sources(claims, [other], binding_caps())
    is Err(MissingPolicy(0, _)),
  )
  let w = source_wires()
  w.push(
    @wire.admit(
      @utf8.encode(
        "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.aggregate-array-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_aggregate_array_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:9a0e7c1509f4a60a751edb4af583db95869fb86e7f42f8c35aadc6a943b92df6\"}",
      ),
      "sha256:9a0e7c1509f4a60a751edb4af583db95869fb86e7f42f8c35aadc6a943b92df6",
      { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
    ).unwrap(),
  )
  assert_true(
    @capacity_host_witness.bind_claim_sources(
      source_program(w),
      [p],
      binding_caps(),
    )
    is Err(InvalidHostSource(15, IdentityMismatch)),
  )
  assert_true(
    @capacity_host_witness.bind_claim_sources(claims, [p], {
      ..binding_caps(),
      max_entries: -1,
    })
    is Err(InvalidBindingLimits),
  )
}

///|
test "equal ceilings from distinct policies retain distinct source ownership" {
  let p = policy(fixture())
  let other = policy(
    "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":2,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}",
  )
  let w = source_wires()
  w.push(
    @wire.admit(
      @utf8.encode(
        "{\"dependencies\":[\"sha256:0dc816e64973fa7621554eec60e0bf75c53e30ba709fd3bc194ad47d1c624382\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0dc816e64973fa7621554eec60e0bf75c53e30ba709fd3bc194ad47d1c624382\"},\"unit\":\"nodes\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:762bb6b69ed3be8451e97961b9e23d10f8d6b1bd06d44ea01d514462b32f5e30\"}",
      ),
      "sha256:762bb6b69ed3be8451e97961b9e23d10f8d6b1bd06d44ea01d514462b32f5e30",
      { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
    ).unwrap(),
  )
  let bound = @capacity_host_witness.bind_claim_sources(
    source_program(w),
    [other, p],
    binding_caps(),
  ).unwrap()
  let selected = @capacity_host_witness.ceiling(
    @capacity_host_witness.source_at(bound, 15).unwrap(),
  )
  assert_eq(@policy.ceiling_value(selected), 1L)
  assert_true(physical_equal(@policy.ceiling_policy(selected), other))
  assert_eq(@capacity_host_witness.source_count(bound), 15)
}
