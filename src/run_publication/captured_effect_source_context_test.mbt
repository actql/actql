///|
// Real publication fixtures exercise the public projection and refusal paths.
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
fn source_context_result_string(
  contract : PublicationContract,
  field : String,
) -> String? {
  match
    @json.object_field(
      captured_test_value(publication_contract_json(contract)),
      field,
    ) {
    Some(@json.String(value)) => Some(value)
    _ => None
  }
}

///|
test "Source context producers preserve the public unbound Result projection and authored facts" {
  for prepared in [false, true] {
    let (chain, captured, preview, source) = source_context_fixture(prepared~)
    // The ordinary artifact constructor has no admitted captured-context association.
    let legacy = admit_captured_effect_source_artifact(
      preview,
      0,
      chain.invocation,
      final_test_source_artifact(chain),
      ordering_test_cid("d"),
    ).unwrap()
    let result = captured_effect_source_result_from_original_capture(
      preview,
      0,
      chain.invocation,
      source,
      captured,
      ordering_test_cid("d"),
    ).unwrap()
    let legacy_result = captured_effect_source_result_from_original_capture(
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
      publication_contract_json(legacy_result),
    )
    for field in ["logical_result_cid", "result_schema_cid"] {
      let expected = source_context_result_string(chain.artifact, field)
      assert_true(expected is Some(_))
      assert_eq(source_context_result_string(result, field), expected)
    }
  }
}

///|
test "separately admitted equal capture Preview and invocation retain full projection semantics" {
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
    let result = captured_effect_source_result_from_original_capture(
      selected_preview,
      0,
      invocation,
      source,
      candidate,
      ordering_test_cid("d"),
    ).unwrap()
    assert_eq(
      source_context_result_string(result, "logical_result_cid"),
      source_context_result_string(chain.artifact, "logical_result_cid"),
    )
  }
}

///|
test "Source context reuse preserves explicit small limits and foreign member Store artifact and context refusal" {
  let (chain, captured, preview, source) = source_context_fixture()
  let (bytes, nodes, depth) = publication_contract_wire_usage(captured).unwrap()
  assert_true(bytes > 1024 && nodes > 1 && depth > 1)
  for
    (small_bytes, small_nodes, small_depth) in [
      (1, nodes, depth),
      (1024, nodes, depth),
      (bytes, 1, depth),
      (bytes, nodes, 1),
    ] {
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
  let table_preview = final_test_preview(chain, plan=false, table=true)
  let foreign_source = final_test_source(chain, table_preview, table=true)
  assert_true(
    captured_effect_source_result_from_original_capture(
      preview,
      0,
      chain.invocation,
      foreign_source,
      captured,
      ordering_test_cid("d"),
    )
    is Err(_),
  )
  let foreign_capture = final_test_captured(chain, table=true)
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
