///|
fn manifest_material_root_inputs(
  provenance_count : Int,
) -> PublicationRootInputs {
  let fixture = inventory_fixture(1, provenance_count~)
  let template = inventory_fixture_cid("1")
  let invocation = seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    template +
    "\",\"observation_set_cid\":\"" +
    inventory_fixture_cid("4") +
    "\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let run = seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"run\",\"compiled_plan_cid\":\"" +
    inventory_fixture_cid("1") +
    "\",\"invocation_template_cid\":\"" +
    template +
    "\",\"authorization_context_cid\":\"" +
    inventory_fixture_cid("2") +
    "\",\"input_artifact_set_cid\":\"" +
    inventory_fixture_cid("3") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\",\"valid_until\":\"2026-09-18T04:00:00.000Z\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let artifact_body = @json.object_without_field(
    fixture.artifacts[0].value,
    fixture.artifacts[0].identity_field,
  ).unwrap()
  let wire = @json.stringify_value(artifact_body, 65536, 4096, 32) catch {
    _ => abort("Invalid original Artifact fixture")
  }
  let artifact = seal_publication_contract(
    "result_artifact",
    wire.replace(old=inventory_fixture_cid("b"), new=invocation.identity),
    65536,
    4096,
    32,
  ).unwrap()
  let manifest = issue_result_manifest(
    run,
    invocation,
    fixture.definitions,
    [artifact],
    65536,
    4096,
    32,
  ).unwrap()
  {
    run_definition: run,
    invocation,
    definitions: fixture.definitions,
    artifacts: [artifact],
    manifest,
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
}

///|
fn manifest_material_root_work(
  inputs : PublicationRootInputs,
  cold : Bool,
) -> Int raise {
  let original = if cold {
    {
      ..inputs,
      manifest: admit_publication_contract(
        "result_manifest",
        inputs.manifest.wire,
        65536,
        4096,
        32,
      ).unwrap(),
    }
  } else {
    inputs
  }
  // Use the existing convenience budget: canonical stream buffers alone need
  // more than the initial fixed Root frame. Product limits are unchanged.
  let root = start_publication_root_preparation(
    original,
    publication_evidence_workspace(original.max_nodes),
  )
  let mut total = 0
  for _ in 0..<100000 {
    let (done, used) = root.advance(1).unwrap()
    assert_true(used > 0 && used <= 1)
    total += used
    if done {
      root.cancel()
      assert_true(root.inputs is None)
      assert_true(root.results is None)
      return total
    }
  }
  abort("Finite Root fixture did not complete")
}

///|
test "issued Manifest Root retains original child work independent of payload size" {
  let small = manifest_material_root_inputs(1)
  let large = manifest_material_root_inputs(129)
  let small_work = manifest_material_root_work(small, false)
  let large_work = manifest_material_root_work(large, false)
  assert_eq(large_work, small_work)
  // One declared Result: the fixed Root/reference/name/binding phases, with
  // no second traversal of that exact admitted immutable Artifact.
  assert_eq(small_work, 17)
  assert_true(manifest_material_root_work(large, true) > large_work)
}

///|
fn manifest_material_text_issuer(
  inputs : PublicationRootInputs,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, ResultManifestIssuanceIssue] {
  let entries = inputs.definitions.mapi((i, definition) => {
    name: contract_string(definition, "result_name").unwrap(),
    artifact: inputs.artifacts[i],
  })
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(ManifestIssuanceEncoding)
  }
  emit_result_manifest_body(
    inputs.run_definition.identity,
    inputs.invocation.identity,
    entries,
    writer,
  ) catch {
    _ => return Err(ManifestIssuanceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(ManifestIssuanceEncoding)
  }
  let contract = match
    seal_publication_contract(
      "result_manifest", body, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ManifestIssuanceContract(issue))
  }
  match
    validate_run_publication_chain(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.artifacts,
      contract,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => Ok(contract)
    Err(issue) => Err(ManifestIssuanceChain(issue))
  }
}

///|
test "Manifest material preserves complete wire CID and tighter-bound failures" {
  let inputs = manifest_material_root_inputs(129)
  let original = manifest_material_text_issuer(inputs, 65536, 4096, 32).unwrap()
  assert_eq(inputs.manifest.wire, original.wire)
  assert_eq(inputs.manifest.identity, original.identity)
  for
    (bytes, nodes, depth) in [
      (0, 4096, 32),
      (100, 4096, 32),
      (65536, 1, 32),
      (65536, 32, 32),
      (65536, 4096, 1),
      (65536, 4096, 2),
    ] {
    let actual = issue_result_manifest(
      inputs.run_definition,
      inputs.invocation,
      inputs.definitions,
      inputs.artifacts,
      bytes,
      nodes,
      depth,
    )
    let expected = manifest_material_text_issuer(inputs, bytes, nodes, depth)
    guard expected is Err(expected) else {
      fail("Expected an actual text-issuer refusal")
    }
    guard actual is Err(actual) else {
      fail("Retained material bypassed a real limit")
    }
    assert_eq(actual, expected)
  }
}

///|
test "Manifest original child reuse keeps cold unmeasured and changed-child full paths" {
  let inputs = manifest_material_root_inputs(129)
  let known = manifest_material_root_work(inputs, false)
  assert_true(manifest_material_root_work(inputs, true) > known)
  let unmeasured = { ..inputs.artifacts[0], wire_usage: None, }
  assert_true(
    manifest_material_root_work({ ..inputs, artifacts: [unmeasured], }, false) >
    known,
  )
  let body = @json.object_without_field(
    inputs.artifacts[0].value,
    inputs.artifacts[0].identity_field,
  ).unwrap()
  let wire = @json.stringify_value(body, 65536, 4096, 32) catch {
    _ => abort("Invalid changed Artifact fixture")
  }
  let changed = seal_publication_contract(
    "result_artifact",
    wire.replace(old=inventory_fixture_cid("3"), new=inventory_fixture_cid("f")),
    65536,
    4096,
    32,
  ).unwrap()
  let root = start_publication_root_preparation(
    { ..inputs, artifacts: [changed], },
    publication_evidence_workspace(4096),
  )
  let mut rejected = false
  for _ in 0..<100000 {
    match root.advance(1) {
      Err(issue) => {
        assert_eq(issue, EvidenceRoot(ChainArtifactMismatch("result_0")))
        rejected = true
        break
      }
      Ok((done, _)) => assert_false(done)
    }
  }
  assert_true(rejected)
  root.cancel()
  let tampered = inputs.manifest.wire.replace(
    old=inputs.artifacts[0].identity,
    new=inventory_fixture_cid("f"),
  )
  assert_true(
    admit_publication_contract("result_manifest", tampered, 65536, 4096, 32)
    is Err(_),
  )
}

///|
test "Manifest material keeps original noncanonical-name diagnostics" {
  let inputs = manifest_material_root_inputs(1)
  // Generic admitted Result DATA can have a spelling refused by the narrower
  // ResultDefinition constructor. Keep its original Manifest diagnostic.
  let definition = seal_publication_contract(
    "result_definition",
    "{\"version\":\"actql-result-definition/0.1\",\"program_definition_cid\":\"" +
    inventory_fixture_cid("1") +
    "\",\"result_name\":\"e\u0301\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let body = @json.object_without_field(
    inputs.artifacts[0].value,
    inputs.artifacts[0].identity_field,
  ).unwrap()
  let wire = @json.stringify_value(body, 65536, 4096, 32) catch {
    _ => abort("Invalid original Artifact fixture")
  }
  let artifact = seal_publication_contract(
    "result_artifact",
    wire.replace(old=inputs.definitions[0].identity, new=definition.identity),
    65536,
    4096,
    32,
  ).unwrap()
  let named = { ..inputs, definitions: [definition], artifacts: [artifact], }
  let expected = manifest_material_text_issuer(named, 65536, 4096, 32)
  let actual = issue_result_manifest(
    named.run_definition,
    named.invocation,
    named.definitions,
    named.artifacts,
    65536,
    4096,
    32,
  )
  guard expected is Err(expected) else {
    fail("Original spelling should retain its refusal")
  }
  guard actual is Err(actual) else {
    fail("Material must not invent an accepted name")
  }
  assert_eq(actual, expected)
}
