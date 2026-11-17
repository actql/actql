///|
fn prepared_source_test_project(
  chain : CapturedRunTestChain,
  captured : PublicationContract,
  prepared : PreparedCapturedEffectRun,
  preview : EffectPreviewIdentity,
  indices : Array[Int],
  artifacts : Array[PublicationContract],
  store : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
  invocation? : PublicationContract? = None,
) -> Result[Array[CapturedEffectSourceArtifact], RunEvidenceChainIssue] {
  prepared_captured_effect_run_sources(
    chain.run,
    invocation.unwrap_or(chain.invocation),
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    captured,
    prepared,
    preview,
    indices,
    artifacts,
    store,
    bytes,
    nodes,
    depth,
  )
}

///|
test "prepared Source combined call preserves legacy Result and Table binding semantics without a standing proof" {
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
    let sources = prepared_source_test_project(
      chain,
      captured,
      prepared,
      preview,
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
test "prepared Source combined call rejects foreign capture changed chain body Store coverage and insufficient limits" {
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
        final_test_preview(chain, table=true, plan=false),
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
        chain.manifest,
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
        1,
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
        1,
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
        1,
      ),
    ] {
    assert_true(
      prepared_source_test_project(
        chain,
        other_captured,
        prepared,
        other_preview,
        indices,
        artifacts,
        store,
        bytes,
        nodes,
        depth,
        invocation=Some(invocation),
      )
      is Err(_),
    )
  }
  // A previous successful projection cannot cache acceptance for changed DATA.
  prepared_source_test_project(
    chain,
    captured,
    prepared,
    preview,
    [0],
    [artifact],
    ordering_test_cid("d"),
    65536,
    4096,
    32,
  ).unwrap()
  |> ignore
  assert_true(
    prepared_source_test_project(
      chain,
      captured,
      prepared,
      preview,
      [0],
      [artifact],
      ordering_test_cid("e"),
      65536,
      4096,
      32,
    )
    is Err(_),
  )
}

///|
// Existing synthetic reference-closure fixture, expanded to actual N distinct
// members. No provider, send, authorisation or physical holding is executed.
fn prepared_source_test_members(
  chain : CapturedRunTestChain,
  n : Int,
) -> (PublicationContract, EffectPreviewIdentity, Array[PublicationContract]) {
  let placeholder = ordering_test_cid("a")
  let raw = final_test_preview_wire(chain, placeholder, placeholder)
  let value = captured_test_value(raw)
  let effects = match @json.object_field(value, "effects") {
    Some(@json.Array(items)) => items
    _ => abort("Missing fixture effects")
  }
  let original = captured_test_wire(@json.array_values(effects)[0])
  let build = fn(cids : Array[String], preview_cid : String) -> String {
    let wires = []
    let identity_pins = [
      "01", "02", "03", "04", "05", "06", "07", "08", "09", "0a", "0b", "0c", "0d",
      "0e", "0f", "10", "11",
    ]
    for index in 0..<n {
      wires.push(
        original
        .replace(
          old="\"effect_id\":\"WriteOne\"",
          new="\"effect_id\":\"Write" + index.to_string() + "\"",
        )
        .replace(
          old="\"effect_identity_cid\":\"" + placeholder + "\"",
          new="\"effect_identity_cid\":\"sha256:" +
            "0".repeat(62) +
            identity_pins[index] +
            "\"",
        )
        .replace(
          old="\"effect_member_preview_cid\":\"" + placeholder + "\"",
          new="\"effect_member_preview_cid\":\"" + cids[index] + "\"",
        ),
      )
    }
    raw
    .replace(
      old="\"effects\":[" + original + "]",
      new="\"effects\":[" + wires.join(",") + "]",
    )
    .replace(
      old="\"effect_preview_cid\":\"" + placeholder + "\"",
      new="\"effect_preview_cid\":\"" + preview_cid + "\"",
    )
  }
  let (_, members) = derive_effect_preview_identities(
    build(Array::make(n, placeholder), placeholder),
    2097152,
    100000,
    32,
  ).unwrap()
  let (preview_cid, _) = derive_effect_preview_identities(
    build(members, placeholder),
    2097152,
    100000,
    32,
  ).unwrap()
  let preview = admit_effect_preview_identity(
    build(members, preview_cid),
    publication_contract_identity(chain.run),
    run_evidence_value_identity(chain.authoring),
    2097152,
    100000,
    32,
  ).unwrap()
  let artifact = final_test_source_artifact(chain)
  let sources = []
  let locals = []
  let plans = []
  for index in 0..<n {
    let source = admit_captured_effect_source_artifact(
      preview,
      index,
      chain.invocation,
      artifact,
      ordering_test_cid("d"),
    ).unwrap()
    sources.push(source)
    locals.push(final_test_local_source(chain, source))
    plans.push(("Write" + index.to_string(), "{}"))
  }
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let captured = issue_effectful_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    sources,
    locals,
    [],
    chain.authoring,
    chain.models,
    preview,
    plans,
    2097152,
    100000,
    32,
  ).unwrap()
  (captured, preview, Array::make(n, artifact))
}

///|
test "prepared Source combined call validates one actual N-member chain instead of 2N repeated whole-context Source entries" {
  for n in [1, 2, 17] {
    let chain = captured_run_test_chain()
    let (captured, preview, artifacts) = prepared_source_test_members(chain, n)
    let prepared = prepare_recovered_captured_effect_run(
      captured,
      2097152,
      100000,
      32,
      _ => true,
    ).unwrap()
    let indices = Array::makei(n, index => index)
    let projected = prepared_source_test_project(
      chain,
      captured,
      prepared,
      preview,
      indices,
      artifacts,
      ordering_test_cid("d"),
      2097152,
      100000,
      32,
    ).unwrap()
    assert_eq(projected.length(), n)
    assert_true(
      captured_effect_source_inventory_from_capture_valid(
        preview,
        indices,
        artifacts,
        chain.invocation,
        captured,
        ordering_test_cid("d"),
        2097152,
        100000,
        32,
      ),
    )
    let mut whole_source_entries = n // Actual inventory validator visits N.
    for index in 0..<n {
      let legacy = admit_captured_effect_source_from_capture(
        preview,
        index,
        chain.invocation,
        artifacts[index],
        captured,
        ordering_test_cid("d"),
        2097152,
        100000,
        32,
      ).unwrap()
      whole_source_entries += 1
      assert_eq(
        captured_effect_source_holding_cid(projected[index]),
        captured_effect_source_holding_cid(legacy),
      )
    }
    assert_eq(whole_source_entries, 2 * n)
  }
}
