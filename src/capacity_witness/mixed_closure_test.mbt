// Independent Node SHA-256 fixtures; synthetic sources do not prove authority.

///|
fn mixed_witnesses() -> Array[WireWitness] {
  [
    claim_fixture(
      "{\"dependencies\":[\"sha256:c456c49f52e3cb4b7e8654af1306e5db700e9ccf540a55077d6daa3ea7e2c2a2\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:c456c49f52e3cb4b7e8654af1306e5db700e9ccf540a55077d6daa3ea7e2c2a2\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:c456c49f52e3cb4b7e8654af1306e5db700e9ccf540a55077d6daa3ea7e2c2a2\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ed70362796bb6a215d48d55cd53238fc886051726bdf372b40a4fba4e2568a1a\"}",
      "sha256:ed70362796bb6a215d48d55cd53238fc886051726bdf372b40a4fba4e2568a1a",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\"],\"derivation\":{\"input\":\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:c966f138be0add59b4dc17dbb10ba627e493ea4d303e3e8f8e44fe4f6448cebe\"}",
      "sha256:c966f138be0add59b4dc17dbb10ba627e493ea4d303e3e8f8e44fe4f6448cebe",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.inputs.g.max_nodes\"},\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f136d7e1843b71327018718bcf660a0c45841262800629ec624c89b8d3d9fe5f\"}",
      "sha256:f136d7e1843b71327018718bcf660a0c45841262800629ec624c89b8d3d9fe5f",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}",
      "sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84",
    ),
    claim_fixture(
      "{\"dependencies\":[\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\"}",
      "sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11",
    ),
  ]
}

///|
fn mixed_artifacts() -> Array[(Bytes, String)] {
  [
    (
      @utf8.encode(
        "{\"author_guard_binding\":\"binding\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\"},{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"source_path\":\"$.inputs.g.max_nodes\"},\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f136d7e1843b71327018718bcf660a0c45841262800629ec624c89b8d3d9fe5f\"}],\"effective_max\":5,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:c456c49f52e3cb4b7e8654af1306e5db700e9ccf540a55077d6daa3ea7e2c2a2\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
      ),
      "sha256:c456c49f52e3cb4b7e8654af1306e5db700e9ccf540a55077d6daa3ea7e2c2a2",
    ),
    (
      @utf8.encode(
        "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}],\"effective_max\":10,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
      ),
      "sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061",
    ),
  ]
}

///|
fn mixed_caps() -> MixedLimits {
  {
    max_entities: 20,
    max_references: 100,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 10,
  }
}

///|
test "mixed closure binds forward preflight limits and retains original claims" {
  let witnesses = mixed_witnesses()
  let artifacts = mixed_artifacts()
  assert_true(
    check_arithmetic_claims(witnesses, {
      max_witnesses: 20,
      max_references: 100,
    })
    is Err(UnresolvedEnforcement(_, _)),
  )
  let result = check_mixed_claims(witnesses, artifacts, mixed_caps()).unwrap()
  assert_eq(claim_count(mixed_arithmetic(result)), 5)
  assert_eq(mixed_limit_count(result), 2)
  assert_eq(limit_cid(mixed_enforced_limit(result, 0).unwrap()), artifacts[0].1)
  assert_eq(limit_cid(mixed_enforced_limit(result, 4).unwrap()), artifacts[1].1)
  assert_true(mixed_enforced_limit(result, 1) is None)
  assert_true(mixed_enforced_limit(result, -1) is None)
  assert_true(mixed_enforced_limit(result, 5) is None)
  assert_true(
    physical_equal(claim_at(mixed_arithmetic(result), 0).unwrap(), witnesses[0]),
  )
  let (references, bytes, nodes) = mixed_usage(result)
  let exact = {
    ..mixed_caps(),
    max_entities: 7,
    max_references: references,
    max_bytes: bytes,
    max_nodes: nodes,
  }
  assert_true(check_mixed_claims(witnesses, artifacts, exact) is Ok(_))
  let low : Array[MixedLimits] = [
    { ..exact, max_entities: 6, },
    { ..exact, max_references: references - 1, },
    { ..exact, max_bytes: bytes - 1, },
    { ..exact, max_nodes: nodes - 1, },
  ]
  for cap in low {
    assert_true(check_mixed_claims(witnesses, artifacts, cap) is Err(_))
  }
  witnesses.clear()
  artifacts.clear()
  assert_eq(claim_count(mixed_arithmetic(result)), 5)
  assert_eq(mixed_limit_count(result), 2)
}

///|
test "mixed closure rejects missing duplicate and mismatched enforcement claims" {
  let w = mixed_witnesses()
  let a = mixed_artifacts()
  assert_true(
    check_mixed_claims(w, [], mixed_caps()) is Err(MissingLimit(_, _)),
  )
  assert_true(
    check_mixed_claims(w, [a[0], a[1], a[0]], mixed_caps())
    is Err(DuplicateLimit(_)),
  )
  for
    (body, id) in [
      (
        "{\"dependencies\":[\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":9,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ae0a9616c4af6907d62d16ffc2e8a89370c23486645aa28ce1f422892bad43f7\"}",
        "sha256:ae0a9616c4af6907d62d16ffc2e8a89370c23486645aa28ce1f422892bad43f7",
      ),
      (
        "{\"dependencies\":[\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"semantic_ref\":\"g\"},\"unit\":\"rows\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:22e5de10f59022cd28acde2b73d1b87f40a56ef2427f272f7b5bf785de9efaca\"}",
        "sha256:22e5de10f59022cd28acde2b73d1b87f40a56ef2427f272f7b5bf785de9efaca",
      ),
      (
        "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:9c48322c8eb3235a1d472b3a09598c7607fd11540d3fe317658c8d716d4b7278\"}",
        "sha256:9c48322c8eb3235a1d472b3a09598c7607fd11540d3fe317658c8d716d4b7278",
      ),
      (
        "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f03551c43fe3199eb4af0ece8395f6013e29c1f1b34b0de8c43680e8ef23c37c\"}",
        "sha256:f03551c43fe3199eb4af0ece8395f6013e29c1f1b34b0de8c43680e8ef23c37c",
      ),
    ] {
    let bad = claim_fixture(body, id)
    assert_true(
      check_mixed_claims([w[3], bad], [a[1]], mixed_caps())
      is Err(InvalidEnforcedClaim(1)),
    )
  }
  let static_witness = claim_fixture(
    "{\"dependencies\":[\"sha256:40c4dad2b5d1a11d7bc7db626137c1467dc01543c5eaf3c255402436d9dd59d0\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:40c4dad2b5d1a11d7bc7db626137c1467dc01543c5eaf3c255402436d9dd59d0\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:40c4dad2b5d1a11d7bc7db626137c1467dc01543c5eaf3c255402436d9dd59d0\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:d443da0727f08d4fa10d24400119abe31a3b2b532c65c6a233b265baa8691fa4\"}",
    "sha256:d443da0727f08d4fa10d24400119abe31a3b2b532c65c6a233b265baa8691fa4",
  )
  let static_limit = (
    @utf8.encode(
      "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}],\"effective_max\":10,\"enforcement\":\"static\",\"resolved_limit_cid\":\"sha256:40c4dad2b5d1a11d7bc7db626137c1467dc01543c5eaf3c255402436d9dd59d0\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
    ),
    "sha256:40c4dad2b5d1a11d7bc7db626137c1467dc01543c5eaf3c255402436d9dd59d0",
  )
  assert_true(
    check_mixed_claims([w[3], static_witness], [static_limit], mixed_caps())
    is Err(InvalidEnforcedClaim(1)),
  )
  assert_true(
    check_mixed_claims(w, [a[1]], mixed_caps()) is Err(MissingLimit(_, _)),
  )
  assert_true(
    check_mixed_claims(w, a, { ..mixed_caps(), max_depth: -1, })
    is Err(InvalidMixedLimits),
  )
}
