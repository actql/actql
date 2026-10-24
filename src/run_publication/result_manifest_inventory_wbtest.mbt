///|
fn manifest_inventory_fixture(
  count : Int,
) -> (
  PublicationContract,
  PublicationContract,
  Array[PublicationContract],
  Array[PublicationContract],
) {
  let root = manifest_material_root_inputs(1)
  let fixture = inventory_fixture(count)
  let artifacts = fixture.artifacts.map(original => {
    let body = @json.object_without_field(
      original.value,
      original.identity_field,
    ).unwrap()
    let wire = @json.stringify_value(body, 65536, 4096, 32) catch {
      _ => abort("Invalid original Artifact fixture")
    }
    seal_publication_contract(
      "result_artifact",
      wire.replace(old=inventory_fixture_cid("b"), new=root.invocation.identity),
      65536,
      4096,
      32,
    ).unwrap()
  })
  (root.run_definition, root.invocation, fixture.definitions, artifacts)
}

///|
test "Manifest inventory pairing is independent of the original Artifact order" {
  let (run, invocation, definitions, artifacts) = manifest_inventory_fixture(32)
  let reversed = Array::makei(artifacts.length(), index => {
    artifacts[artifacts.length() - index - 1]
  })
  let issued = issue_result_manifest(
    run, invocation, definitions, reversed, 262144, 16384, 32,
  ).unwrap()
  let results = @json.object_field(issued.value, "results").unwrap()
  assert_eq(@json.object_field_count(results), Some(32))
  for index in 0..<definitions.length() {
    let name = "result_\{index}"
    let actual = @json.object_field(results, name).unwrap()
    // Expected correspondence comes from the separately retained input pair,
    // not from a lookup or ordering produced by the Manifest implementation.
    assert_true(physical_equal(actual, artifacts[index].value))
    assert_eq(
      evidence_string(actual, "result_definition_cid"),
      Some(definitions[index].identity),
    )
  }
}

///|
test "Manifest inventory keeps duplicate and wrong-contract failure precedence" {
  let (run, invocation, definitions, artifacts) = manifest_inventory_fixture(2)
  let first = definitions[0]
  let second = definitions[1]
  let first_artifact = artifacts[0]
  let second_artifact = artifacts[1]
  let issue = fn(definitions, artifacts) {
    issue_result_manifest(
      run, invocation, definitions, artifacts, 65536, 4096, 32,
    )
  }
  assert_true(
    issue([first, first], [first_artifact, second_artifact])
    is Err(ManifestIssuanceDuplicateResult("result_0")),
  )
  assert_true(
    issue([first, first], [first_artifact, first_artifact])
    is Err(ManifestIssuanceInventoryMismatch),
  )
  // An admitted Definition carries the same definition CID as its Artifact,
  // but remains a different contract kind. Matching alone cannot upgrade it.
  assert_true(
    issue([first, second], [first, second_artifact])
    is Err(ManifestIssuanceWrongContract),
  )
  assert_true(
    issue([first, second], [first_artifact, first])
    is Err(ManifestIssuanceInventoryMismatch),
  )
  assert_true(
    issue([first_artifact, second], [first_artifact, first_artifact])
    is Err(ManifestIssuanceWrongContract),
  )
}

///|
test "Manifest inventory rejects repeated ambiguous and absent original bindings" {
  let (run, invocation, definitions, artifacts) = manifest_inventory_fixture(3)
  for
    selected in [
      [artifacts[0], artifacts[0], artifacts[0]],
      [artifacts[1], artifacts[1], artifacts[2]],
      [artifacts[0], artifacts[1], definitions[2]],
    ] {
    let actual = issue_result_manifest(
      run, invocation, definitions, selected, 65536, 4096, 32,
    )
    match selected[2].name {
      "result_definition" =>
        assert_true(actual is Err(ManifestIssuanceWrongContract))
      _ => assert_true(actual is Err(ManifestIssuanceInventoryMismatch))
    }
  }
}
