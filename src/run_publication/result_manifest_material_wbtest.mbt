///|
fn manifest_material_root_inputs(provenance_count : Int) -> PublicationRootInputs {
  let fixture = inventory_fixture(1, provenance_count~)
  let template = inventory_fixture_cid("1")
  let invocation = seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    template +
    "\",\"observation_set_cid\":\"" +
    inventory_fixture_cid("4") +
    "\"}",
    65536, 4096, 32,
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
    65536, 4096, 32,
  ).unwrap()
  let artifact_body = @json.object_without_field(
    fixture.artifacts[0].value, fixture.artifacts[0].identity_field,
  ).unwrap()
  let wire = @json.stringify_value(artifact_body, 65536, 4096, 32) catch {
    _ => abort("Invalid original Artifact fixture")
  }
  let artifact = seal_publication_contract(
    "result_artifact",
    wire.replace(old=inventory_fixture_cid("b"), new=invocation.identity),
    65536, 4096, 32,
  ).unwrap()
  let manifest = issue_result_manifest(
    run, invocation, fixture.definitions, [artifact], 65536, 4096, 32,
  ).unwrap()
  {
    run_definition: run, invocation, definitions: fixture.definitions,
    artifacts: [artifact], manifest, max_wire_bytes: 65536, max_nodes: 4096,
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
        "result_manifest", inputs.manifest.wire, 65536, 4096, 32,
      ).unwrap(),
    }
  } else {
    inputs
  }
  // Use the existing convenience budget: canonical stream buffers alone need
  // more than the initial fixed Root frame. Product limits are unchanged.
  let root = start_publication_root_preparation(
    original, publication_evidence_workspace(original.max_nodes),
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
  assert_true(manifest_material_root_work(large, true) > large_work)
}
