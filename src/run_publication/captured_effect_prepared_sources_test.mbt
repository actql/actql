///|
fn prepared_source_test_validate(
  chain : CapturedRunTestChain,
  captured : PublicationContract,
  prepared : PreparedCapturedEffectRun,
  preview : EffectPreviewIdentity,
) -> Unit {
  validate_prepared_effectful_computation_evidence_chain(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    captured,
    prepared,
    preview,
    65536,
    4096,
    32,
  ).unwrap()
}

///|
test "prepared Source projection requires the original checked chain and preserves legacy binding semantics" {
  for table in [false, true] {
    let chain = captured_run_test_chain()
    let captured = final_test_captured(chain, table~)
    let preview = final_test_preview(chain, plan=!table, table~)
    let prepared = prepare_recovered_captured_effect_run(
      captured,
      65536,
      4096,
      32,
      _ => true,
    ).unwrap()
    let artifact = final_test_source_artifact(chain, table~)
    assert_true(
      prepared_captured_effect_run_sources(
        captured,
        prepared,
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      )
      is Err(_),
    )
    prepared_source_test_validate(chain, captured, prepared, preview)
    let sources = prepared_captured_effect_run_sources(
      captured,
      prepared,
      preview,
      chain.invocation,
      [0],
      [artifact],
      ordering_test_cid("d"),
      65536,
      4096,
      32,
    ).unwrap()
    let legacy = admit_captured_effect_source_from_capture(
      preview,
      0,
      chain.invocation,
      artifact,
      captured,
      ordering_test_cid("d"),
      65536,
      4096,
      32,
    ).unwrap()
    assert_eq(sources.length(), 1)
    assert_eq(
      captured_effect_source_holding_cid(sources[0]),
      captured_effect_source_holding_cid(legacy),
    )
    assert_eq(
      captured_effect_source_artifact_cid(sources[0]),
      captured_effect_source_artifact_cid(legacy),
    )
  }
}

///|
test "prepared Source projection rejects foreign context limits coverage and changed per-item body" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let prepared = prepare_recovered_captured_effect_run(
    captured,
    65536,
    4096,
    32,
    _ => true,
  ).unwrap()
  let artifact = final_test_source_artifact(chain)
  prepared_source_test_validate(chain, captured, prepared, preview)
  for
    (
      other_captured,
      other_preview,
      invocation,
      indices,
      artifacts,
      store,
      bytes,
      nodes,
      depth,
    ) in [
      (
        final_test_captured(chain),
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        final_test_preview(chain),
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        preview,
        captured_run_test_chain().invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [0, 0],
        [artifact, artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [],
        [],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [0],
        [final_test_source_artifact(chain, table=true)],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("e"),
        65536,
        4096,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65537,
        4096,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4095,
        32,
      ),
      (
        captured,
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        31,
      ),
    ] {
    assert_true(
      prepared_captured_effect_run_sources(
        other_captured, prepared, other_preview, invocation, indices, artifacts,
        store, bytes, nodes, depth,
      )
      is Err(_),
    )
  }
}

///|
test "prepared Source DATA replay performs N member projections after one chain instead of 2N whole-context entries" {
  for n in [1, 17] {
    let chain = captured_run_test_chain()
    let captured = final_test_captured(chain)
    let preview = final_test_preview(chain)
    let prepared = prepare_recovered_captured_effect_run(
      captured,
      65536,
      4096,
      32,
      _ => true,
    ).unwrap()
    let artifact = final_test_source_artifact(chain)
    // Actual Core validators, not elapsed time or a fake Resource receipt.
    // N is repeated immutable one-member DATA projections, not N Effects.
    let mut chain_calls = 0
    prepared_source_test_validate(chain, captured, prepared, preview)
    chain_calls += 1
    let mut member_calls = 0
    let mut legacy_context_entries = 0
    for _ in 0..<n {
      assert_true(
        captured_effect_source_inventory_from_capture_valid(
          preview,
          [0],
          [artifact],
          chain.invocation,
          captured,
          ordering_test_cid("d"),
          65536,
          4096,
          32,
        ),
      )
      legacy_context_entries += 1
      let legacy = admit_captured_effect_source_from_capture(
        preview,
        0,
        chain.invocation,
        artifact,
        captured,
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ).unwrap()
      legacy_context_entries += 1
      let actual = prepared_captured_effect_run_sources(
        captured,
        prepared,
        preview,
        chain.invocation,
        [0],
        [artifact],
        ordering_test_cid("d"),
        65536,
        4096,
        32,
      ).unwrap()
      member_calls += actual.length()
      assert_eq(
        captured_effect_source_holding_cid(actual[0]),
        captured_effect_source_holding_cid(legacy),
      )
    }
    assert_eq(chain_calls, 1)
    assert_eq(member_calls, n)
    assert_eq(legacy_context_entries, 2 * n)
  }
}
