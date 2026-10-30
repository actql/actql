///|
// A closed Source Evidence DATA fixture; no Source/Model authority or I/O.
// Only the schema's existing unconstrained checkpoint DATA varies.
fn infer_original_bound_fixture(
  checkpoint : String,
) -> @publication.RunEvidenceValue {
  let body = "{\"authority_scope_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"checkpoint\":" +
    checkpoint +
    ",\"completeness\":\"complete\",\"consistency_level\":\"immutable_fixture\",\"data_classification\":\"public\",\"effective_data_policy_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"input_logical_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"observed_at\":\"2026-10-30T00:00:00.000Z\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"schema_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"snapshot_ref\":\"fixture\",\"source_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_data_policy_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"source_ref\":\"fixture\",\"source_view_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-source-evidence/0.1\"}"
  @publication.seal_run_evidence_value(
    "source_evidence", body, 200000, 20000, 200,
  ).unwrap()
}

///|
test "original INFER evidence preserves exact byte node and depth envelopes" {
  // Independently counted fixed Source/CID envelope: 1219 ASCII bytes.
  let exact_bytes = infer_original_bound_fixture(
    "\"" + "a".repeat(98781) + "\"",
  )
  assert_eq(@publication.run_evidence_value_json(exact_bytes).length(), 100000)
  let extra_byte = infer_original_bound_fixture("\"" + "a".repeat(98782) + "\"")
  // The closed envelope contains 23 nodes with a scalar checkpoint.
  // Replacing it with an array of N scalar children adds exactly N nodes.
  let exact_nodes = infer_original_bound_fixture("[" + "0,".repeat(9976) + "0]")
  let extra_node = infer_original_bound_fixture("[" + "0,".repeat(9977) + "0]")
  // The existing writer/decoder bound counts open containers, not scalars.
  // Root object plus N nested checkpoint arrays = N + 1 levels.
  let exact_depth = infer_original_bound_fixture(
    "[".repeat(99) + "0" + "]".repeat(99),
  )
  let extra_depth = infer_original_bound_fixture(
    "[".repeat(100) + "0" + "]".repeat(100),
  )
  for evidence in [exact_bytes, exact_nodes, exact_depth] {
    assert_true(
      check_client_infer_original_evidence("source_evidence", evidence) is Ok(_),
    )
    assert_true(
      @publication.admit_run_evidence_value(
        "source_evidence",
        @publication.run_evidence_value_json(evidence),
        100000,
        10000,
        100,
      )
      is Ok(_),
    )
  }
  for evidence in [extra_byte, extra_node, extra_depth] {
    assert_true(
      check_client_infer_original_evidence("source_evidence", evidence)
      is Err(_),
    )
    assert_true(
      @publication.admit_run_evidence_value(
        "source_evidence",
        @publication.run_evidence_value_json(evidence),
        100000,
        10000,
        100,
      )
      is Err(_),
    )
  }
  assert_true(
    check_client_infer_original_evidence("source_input_logical", exact_bytes)
    is Err(_),
  )
}
