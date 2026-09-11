///|
// Deliberately synthetic internal topology: a valid cyclic SHA-256 preimage is
// not constructed. Public admission cannot manufacture these private mutations.
test "mixed dependency traversal rejects a limit depending on its enforced witness" {
  let bytes = b"{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}"
  let original = admit(
    bytes,
    "sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84",
    { max_bytes: 10000, max_nodes: 100, max_depth: 5, },
  ).unwrap()
  let id = "sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061"
  let cyclic = {
    ..original,
    source: Program("g", id),
    derivation: EnforcedCeiling(id),
    dependencies: [id],
  }
  let result = check_mixed_claims(
    [cyclic],
    [
      (
        b"{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.graph-input-nodes\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_graph_input_nodes\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a3a3357de8d1a8d795ba7f889d31aa2c6da1449227adc5e8fe0228f7f7498a84\"}],\"effective_max\":10,\"enforcement\":\"unit_preflight\",\"resolved_limit_cid\":\"sha256:41ad911c5b35c683ce54580bd768ca221acde3e2ef84412b67b46da0a2cc5061\",\"subject_ref\":\"graph-input:g:nodes\",\"unit\":\"nodes\",\"version\":\"actql-resolved-limit/0.1\"}",
        id,
      ),
    ],
    {
      max_entities: 2,
      max_references: 10,
      max_bytes: 10000,
      max_nodes: 100,
      max_depth: 5,
    },
  )
  assert_eq(result.unwrap_err(), CyclicLimitDependencies)
}
