///|
test "original captured Source projection separates whole-capture extent from Command body bounds" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let source = admit_captured_effect_source_from_capture(
    preview,
    0,
    chain.invocation,
    final_test_source_artifact(chain),
    captured,
    ordering_test_cid("d"),
    65536,
    4096,
    32,
  ).unwrap()
  let (bytes, _, _) = publication_contract_wire_usage(captured).unwrap()
  assert_true(bytes > 1024)
  // The independently selected small per-input envelope cannot encode this
  // complete context. It remains a refusal on the explicit legacy interface.
  assert_true(
    captured_effect_source_result_from_capture(
      preview,
      0,
      chain.invocation,
      source,
      captured,
      ordering_test_cid("d"),
      1024,
      4096,
      32,
    )
    is Err(_),
  )
  let result = captured_effect_source_result_from_original_capture(
    preview,
    0,
    chain.invocation,
    source,
    captured,
    ordering_test_cid("d"),
  ).unwrap()
  let expected = captured_effect_source_result_from_capture(
    preview,
    0,
    chain.invocation,
    source,
    captured,
    ordering_test_cid("d"),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    publication_contract_identity(result),
    publication_contract_identity(expected),
  )
  assert_eq(
    publication_contract_json(result),
    publication_contract_json(expected),
  )
  for
    (other_captured, other_invocation, store, member_index) in [
      (captured, chain.invocation, ordering_test_cid("e"), 0),
      (captured, chain.invocation, ordering_test_cid("d"), 1),
      (captured, final_test_captured(chain), ordering_test_cid("d"), 0),
    ] {
    assert_true(
      captured_effect_source_result_from_original_capture(
        preview, member_index, other_invocation, source, other_captured, store,
      )
      is Err(_),
    )
  }
}
