///|
test "stored commit references select original Receipt Captured Run and provenance" {
  let fixture = commit_read_fixture()
  let originals = fixture.originals
  let index = originals[7]
  let (receipt, captured) = public_index_run_observation_cids(index).unwrap()
  assert_eq(receipt, publication_contract_identity(originals[3]))
  assert_eq(captured, publication_contract_identity(originals[4]))
  assert_eq(result_artifact_provenance_count(originals[9]).unwrap(), 1)
  assert_eq(
    result_artifact_provenance_at(originals[9], 0).unwrap(),
    publication_contract_identity(originals[10]),
  )
  // Resolving these references is only preparation. The complete original
  // computation/binding/Receipt/attempt/index chain still has to validate.
  commit_read_complete(fixture.preparation, 10000) |> ignore
  let view = fixture.preparation.finish_view().unwrap()
  assert_true(
    physical_equal(
      fixture.preparation.view_contract(view, 3).unwrap(),
      originals[3],
    ),
  )
  fixture.preparation.release_view(view).unwrap()
  fixture.preparation.cancel()
}

///|
test "stored commit references reject wrong roles and exact provenance boundaries" {
  let fixture = commit_read_fixture()
  for original in fixture.originals {
    if publication_contract_name(original) != "public_index_entry" {
      assert_true(
        public_index_run_observation_cids(original)
        is Err(DeliveryIssuanceWrongContract("public_index_entry")),
      )
    }
    if publication_contract_name(original) != "result_artifact" {
      assert_true(
        result_artifact_provenance_count(original)
        is Err(DeliveryIssuanceWrongContract("result_artifact")),
      )
      assert_true(
        result_artifact_provenance_at(original, 0)
        is Err(DeliveryIssuanceWrongContract("result_artifact")),
      )
    }
  }
  let artifact = fixture.originals[9]
  assert_true(result_artifact_provenance_at(artifact, -1) is Err(_))
  assert_true(result_artifact_provenance_at(artifact, 1) is Err(_))
  fixture.preparation.cancel()
}

///|
test "retained Run receipt selects only the original index definition and Manifest" {
  let fixture = commit_read_fixture()
  let originals = fixture.originals
  check_original_stored_run_receipt_references(
    originals[7],
    originals[0],
    originals[2],
    originals[3],
  ).unwrap()
  // This projection observes references only. It neither completes the stored
  // validation cursor nor manufactures a Publisher or execution evidence.
  assert_true(fixture.preparation.finish_view() is Err(_))
  for role in 0..<4 {
    let selected = [originals[7], originals[0], originals[2], originals[3]]
    selected[role] = originals[1]
    assert_true(
      check_original_stored_run_receipt_references(
        selected[0],
        selected[1],
        selected[2],
        selected[3],
      )
      is Err(DeliveryIssuanceWrongContract("retained_run_receipt")),
    )
  }
  fixture.preparation.cancel()
}

///|
test "retained Run receipt refuses a changed original reference without a replacement receipt" {
  let fixture = commit_read_fixture()
  let original = fixture.originals
  let receipt = original[3]
  let body = @json.object_without_field(
    captured_test_value(publication_contract_json(receipt)),
    "receipt_identity_cid",
  ).unwrap()
  // The admitted but different receipt cannot stand in for the exact original
  // selected by this committed index, even if its own canonical hash is valid.
  let changed = seal_publication_contract(
    "run_receipt",
    captured_test_wire(body).replace(
      old="\"result_manifest_cid\":\"" +
        publication_contract_identity(original[2]) +
        "\"",
      new="\"result_manifest_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    check_original_stored_run_receipt_references(
      original[7],
      original[0],
      original[2],
      changed,
    )
    is Err(DeliveryIssuanceReferenceMismatch("retained_run_receipt.index")),
  )
  fixture.preparation.cancel()
}

///|
test "retained Run receipt rejects foreign roots even when the index names that receipt" {
  let fixture = commit_read_fixture()
  let original = fixture.originals
  let receipt = original[3]
  let receipt_body = @json.object_without_field(
    captured_test_value(publication_contract_json(receipt)),
    "receipt_identity_cid",
  ).unwrap()
  let index_body = @json.object_without_field(
    captured_test_value(publication_contract_json(original[7])),
    "public_index_entry_cid",
  ).unwrap()
  for
    (field, issue) in [
      ("invocation_cid", "invocation"),
      ("compiled_plan_cid", "compiled_plan"),
      ("result_manifest_cid", "manifest"),
    ] {
    let changed_receipt = seal_publication_contract(
      "run_receipt",
      captured_test_wire(
        @json.object_with_string_field(
          @json.object_without_field(receipt_body, field).unwrap(),
          field,
          ordering_test_cid("f"),
        ).unwrap(),
      ),
      65536,
      4096,
      32,
    ).unwrap()
    let changed_index = seal_publication_contract(
      "public_index_entry",
      captured_test_wire(
        @json.object_with_string_field(
          @json.object_without_field(index_body, "run_receipt_cid").unwrap(),
          "run_receipt_cid",
          publication_contract_identity(changed_receipt),
        ).unwrap(),
      ),
      65536,
      4096,
      32,
    ).unwrap()
    assert_eq(
      check_original_stored_run_receipt_references(
        changed_index,
        original[0],
        original[2],
        changed_receipt,
      ),
      Err(DeliveryIssuanceReferenceMismatch("retained_run_receipt." + issue)),
    )
  }
  fixture.preparation.cancel()
}

///|
fn stored_reference_artifact(provenance : String) -> PublicationContract {
  let cid = ordering_test_cid
  seal_publication_contract(
    "result_artifact",
    "{\"actual_completeness\":\"complete\",\"actual_row_count\":1,\"effective_data_policy_cid\":\"" +
    cid("1") +
    "\",\"effective_retention_policy_cid\":\"" +
    cid("2") +
    "\",\"invocation_cid\":\"" +
    cid("3") +
    "\",\"logical_result_cid\":\"" +
    cid("4") +
    "\",\"ordering_evidence_cid\":\"" +
    cid("5") +
    "\",\"provenance_evidence_cids\":" +
    provenance +
    ",\"result_definition_cid\":\"" +
    cid("6") +
    "\",\"result_schema_cid\":\"" +
    cid("7") +
    "\",\"version\":\"actql-result-artifact/0.1\"}",
    65536,
    4096,
    32,
  ).unwrap()
}

///|
test "stored commit provenance preserves original empty list and received order" {
  let empty = stored_reference_artifact("[]")
  assert_eq(result_artifact_provenance_count(empty).unwrap(), 0)
  assert_true(result_artifact_provenance_at(empty, 0) is Err(_))
  let first = ordering_test_cid("9")
  let second = ordering_test_cid("8")
  let artifact = stored_reference_artifact(
    "[\"" + first + "\",\"" + second + "\"]",
  )
  assert_eq(result_artifact_provenance_count(artifact).unwrap(), 2)
  assert_eq(result_artifact_provenance_at(artifact, 0).unwrap(), first)
  assert_eq(result_artifact_provenance_at(artifact, 1).unwrap(), second)
  assert_true(result_artifact_provenance_at(artifact, 2) is Err(_))
}
