///|
// Candidate mutation only: remove exactly the selected original's outer
// identity before asking the same Owner to seal the changed body. Expected
// names and mismatch fields below remain independent literals.
fn indexed_names_changed_contract(
  original : PublicationContract,
  changed_wire : String,
) -> PublicationContract raise {
  let identity_entry = "\"" +
    publication_contract_identity_field(original) +
    "\":\"" +
    publication_contract_identity(original) +
    "\","
  assert_true(changed_wire.contains(identity_entry))
  seal_publication_contract(
    publication_contract_name(original),
    changed_wire.replace(old=identity_entry, new=""),
    32768,
    256,
    16,
  ).unwrap()
}

///|
test "indexed manifest names retain exact bounded existing JSON projection" {
  let (index, manifest, _) = delivery_test_root()
  assert_eq(
    public_index_manifest_result_names_json(index, manifest, 10, 2, 1),
    Ok("[\"answer\"]"),
  )
  for (bytes, nodes, depth) in [(9, 2, 1), (10, 1, 1), (10, 2, 0)] {
    assert_true(
      public_index_manifest_result_names_json(
        index, manifest, bytes, nodes, depth,
      )
      is Err(DeliveryIssuanceEncoding),
    )
  }
}

///|
test "indexed manifest names reject wrong contract and each original reference" {
  let (index, manifest, artifact) = delivery_test_root()
  assert_true(
    public_index_manifest_result_names_json(artifact, manifest, 4096, 64, 8)
    is Err(DeliveryIssuanceWrongContract("public_index_entry")),
  )
  assert_true(
    public_index_manifest_result_names_json(index, artifact, 4096, 64, 8)
    is Err(DeliveryIssuanceWrongContract("result_manifest")),
  )
  for
    (field, original) in [
      ("run_definition_cid", delivery_test_cid("3")),
      ("invocation_cid", delivery_test_cid("b")),
    ] {
    let changed = indexed_names_changed_contract(
      manifest,
      publication_contract_json(manifest).replace(
        old="\"" + field + "\":\"" + original + "\"",
        new="\"" + field + "\":\"" + delivery_test_cid("0") + "\"",
      ),
    )
    assert_true(
      public_index_manifest_result_names_json(index, changed, 4096, 64, 8)
      is Err(DeliveryIssuanceReferenceMismatch("result_manifest_cid")),
    )
    let corresponding = indexed_names_changed_contract(
      index,
      publication_contract_json(index).replace(
        old=publication_contract_identity(manifest),
        new=publication_contract_identity(changed),
      ),
    )
    assert_true(
      public_index_manifest_result_names_json(
        corresponding, changed, 4096, 64, 8,
      )
      is Err(DeliveryIssuanceReferenceMismatch(actual)) &&
      actual == field,
    )
  }
}

///|
test "indexed manifest names preserve Unicode names and UTF16 order" {
  let (index, manifest, artifact) = delivery_test_root()
  let changed = indexed_names_changed_contract(
    manifest,
    publication_contract_json(manifest).replace(
      old="\"answer\":" + publication_contract_json(artifact),
      new="\"\u{e000}\":" +
        publication_contract_json(artifact) +
        ",\"\u{10000}\":" +
        publication_contract_json(artifact),
    ),
  )
  let corresponding = indexed_names_changed_contract(
    index,
    publication_contract_json(index).replace(
      old=publication_contract_identity(manifest),
      new=publication_contract_identity(changed),
    ),
  )
  assert_eq(
    public_index_manifest_result_names_json(corresponding, changed, 64, 8, 4),
    Ok("[\"\u{10000}\",\"\u{e000}\"]"),
  )
}
