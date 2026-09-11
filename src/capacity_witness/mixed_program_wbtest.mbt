///|
// Synthetic internal topology avoids claiming a cyclic SHA-256 preimage.
// The mixed graph alone is acyclic; adding the Program input closes the cycle.
test "combined closure detects cycles passing through Program proof bodies" {
  let host = admit(
    b"{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}",
    "sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84",
    { max_bytes: 10000, max_nodes: 100, max_depth: 5, },
  ).unwrap()
  let enforced = admit(
    b"{\"dependencies\":[\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\"}",
    "sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11",
    { max_bytes: 10000, max_nodes: 100, max_depth: 5, },
  ).unwrap()
  let program = { ..host, source: Program("g", "sha256:" + "0".repeat(64)), }
  let mixed = check_mixed_claims(
    [program, enforced],
    [
      (
        b"{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}],\"effective_max\":10,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
        "sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061",
      ),
    ],
    {
      max_entities: 3,
      max_references: 20,
      max_bytes: 10000,
      max_nodes: 100,
      max_depth: 5,
    },
  ).unwrap()
  let proof : ProgramProofClaim = {
    witness: program,
    form: DerivedInputs,
    inputs: [enforced.cid],
  }
  assert_eq(
    check_mixed_program_claims(mixed, [proof], {
      max_witnesses: 4,
      max_references: 20,
    }).unwrap_err(),
    CyclicProgramInputs,
  )
  let leaf : ProgramProofClaim = { ..proof, inputs: [], }
  assert_true(
    check_mixed_program_claims(mixed, [leaf], {
      max_witnesses: 4,
      max_references: 20,
    })
    is Ok(_),
  )
}
