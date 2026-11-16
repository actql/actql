///|
// Existing real publication fixtures exercise the immutable association only.
// No Store custody, current authorization or physical completion is supplied.
fn source_context_fixture(
  prepared? : Bool = false,
) -> (
  CapturedRunTestChain,
  PublicationContract,
  EffectPreviewIdentity,
  CapturedEffectSourceArtifact,
) {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let artifact = final_test_source_artifact(chain)
  let source = if prepared {
    let original = prepare_recovered_captured_effect_run(
      captured,
      65536,
      4096,
      32,
      _ => true,
    ).unwrap()
    prepared_source_test_project(
      chain,
      captured,
      original,
      preview,
      [0],
      [artifact],
      ordering_test_cid("d"),
      65536,
      4096,
      32,
    ).unwrap()[0]
  } else {
    admit_captured_effect_source_from_capture(
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
  }
  (chain, captured, preview, source)
}

///|
test "Source context association uses exact admitted originals from both producers and preserves legacy Result" {
  for prepared in [false, true] {
    let (chain, captured, preview, source) = source_context_fixture(prepared~)
    let (bytes, nodes, depth) = publication_contract_wire_usage(captured).unwrap()
    assert_true(
      captured_effect_source_context_matches(
        source,
        captured,
        preview,
        chain.invocation,
        0,
        ordering_test_cid("d"),
        bytes,
        nodes,
        depth,
      ),
    )
    let legacy = { ..source, context_binding: None, }
    assert_false(
      captured_effect_source_context_matches(
        legacy,
        captured,
        preview,
        chain.invocation,
        0,
        ordering_test_cid("d"),
        bytes,
        nodes,
        depth,
      ),
    )
    let result = captured_effect_source_result_from_original_capture(
      preview,
      0,
      chain.invocation,
      source,
      captured,
      ordering_test_cid("d"),
    ).unwrap()
    let original_result = captured_effect_source_result_from_original_capture(
      preview,
      0,
      chain.invocation,
      legacy,
      captured,
      ordering_test_cid("d"),
    ).unwrap()
    assert_eq(publication_contract_name(result), "result_artifact")
    assert_eq(
      publication_contract_json(result),
      publication_contract_json(original_result),
    )
    assert_eq(
      contract_string(result, "logical_result_cid"),
      contract_string(chain.artifact, "logical_result_cid"),
    )
    assert_eq(
      contract_string(result, "result_schema_cid"),
      contract_string(chain.artifact, "result_schema_cid"),
    )
  }
}

///|
test "equal-looking admitted capture Preview and invocation do not select another Source context association" {
  let (chain, captured, preview, source) = source_context_fixture()
  let (bytes, nodes, depth) = publication_contract_wire_usage(captured).unwrap()
  let other_captured = admit_publication_contract(
    "captured_run",
    publication_contract_json(captured),
    bytes,
    nodes,
    depth,
  ).unwrap()
  let other_preview = final_test_preview(chain)
  let (invocation_bytes, invocation_nodes, invocation_depth) = publication_contract_wire_usage(
    chain.invocation,
  ).unwrap()
  let other_invocation = admit_publication_contract(
    "run_invocation",
    publication_contract_json(chain.invocation),
    invocation_bytes,
    invocation_nodes,
    invocation_depth,
  ).unwrap()
  for
    (candidate, selected_preview, invocation) in [
      (other_captured, preview, chain.invocation),
      (captured, other_preview, chain.invocation),
      (captured, preview, other_invocation),
    ] {
    assert_false(
      captured_effect_source_context_matches(
        source,
        candidate,
        selected_preview,
        invocation,
        0,
        ordering_test_cid("d"),
        bytes,
        nodes,
        depth,
      ),
    )
    // Equal canonical DATA remains acceptable through the full legacy check;
    // rejecting the reuse predicate does not invent a new semantic refusal.
    let result = captured_effect_source_result_from_original_capture(
      selected_preview,
      0,
      invocation,
      source,
      candidate,
      ordering_test_cid("d"),
    ).unwrap()
    assert_eq(
      contract_string(result, "logical_result_cid"),
      contract_string(chain.artifact, "logical_result_cid"),
    )
  }
}

///|
test "Source context association never waives explicit smaller limits or a foreign member Store or artifact" {
  let (chain, captured, preview, source) = source_context_fixture()
  let (bytes, nodes, depth) = publication_contract_wire_usage(captured).unwrap()
  assert_true(bytes > 1 && nodes > 1 && depth > 1)
  for
    (small_bytes, small_nodes, small_depth) in [
      (1, nodes, depth),
      (bytes, 1, depth),
      (bytes, nodes, 1),
    ] {
    assert_false(
      captured_effect_source_context_matches(
        source,
        captured,
        preview,
        chain.invocation,
        0,
        ordering_test_cid("d"),
        small_bytes,
        small_nodes,
        small_depth,
      ),
    )
    assert_true(
      captured_effect_source_result_from_capture(
        preview,
        0,
        chain.invocation,
        source,
        captured,
        ordering_test_cid("d"),
        small_bytes,
        small_nodes,
        small_depth,
      )
      is Err(_),
    )
  }
  for
    (member, store) in [
      (1, ordering_test_cid("d")),
      (0, ordering_test_cid("e")),
    ] {
    assert_false(
      captured_effect_source_context_matches(
        source,
        captured,
        preview,
        chain.invocation,
        member,
        store,
        bytes,
        nodes,
        depth,
      ),
    )
    assert_true(
      captured_effect_source_result_from_original_capture(
        preview,
        member,
        chain.invocation,
        source,
        captured,
        store,
      )
      is Err(_),
    )
  }
  // Even a private whitebox copy carrying a prior association must still
  // satisfy the actual stored member/artifact correspondence.
  let other_source = {
    ..source,
    artifact: final_test_source_artifact(chain, table=true),
  }
  assert_true(
    captured_effect_source_result_from_original_capture(
      preview,
      0,
      chain.invocation,
      other_source,
      captured,
      ordering_test_cid("d"),
    )
    is Err(_),
  )
  let foreign_capture = final_test_captured(chain, table=true)
  assert_false(
    captured_effect_source_context_matches(
      source,
      foreign_capture,
      preview,
      chain.invocation,
      0,
      ordering_test_cid("d"),
      bytes,
      nodes,
      depth,
    ),
  )
  assert_true(
    captured_effect_source_result_from_original_capture(
      preview,
      0,
      chain.invocation,
      source,
      foreign_capture,
      ordering_test_cid("d"),
    )
    is Err(_),
  )
}
