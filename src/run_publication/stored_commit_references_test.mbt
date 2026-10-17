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
