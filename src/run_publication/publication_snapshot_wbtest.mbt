///|
fn snapshot_index_entry(
  attempt_cid : String,
  identity : String,
) -> PublicationContract {
  let wire = "{\"publication_attempt_cid\":\"" +
    attempt_cid +
    "\",\"public_index_entry_cid\":\"" +
    identity +
    "\"}"
  {
    name: "public_index_entry",
    identity_field: "public_index_entry_cid",
    identity,
    wire,
    value: parse_contract_wire(wire, 4096, 128, 16).unwrap(),
  }
}

///|
fn expect_snapshot_issue(
  record : PublicationContract?,
  index : PublicationIndexObservation,
  expected : PublicationSnapshotIssue,
) -> Unit raise {
  match project_publication_snapshot(record, index) {
    Err(issue) => assert_eq(issue, expected)
    Ok(_) => assert_true(false)
  }
}

///|
test "publication snapshot keeps absence and uncertainty distinct" {
  let absent = project_publication_snapshot(None, IndexConfirmedAbsent).unwrap()
  assert_eq(publication_snapshot_state(absent), NotStarted)
  assert_eq(publication_snapshot_evidence_cid(absent), None)
  let unknown = runtime_record("publication_unknown", 2L)
  let observed = project_publication_snapshot(
    Some(unknown),
    IndexConfirmedAbsent,
  ).unwrap()
  assert_eq(publication_snapshot_state(observed), PublicationUnknown)
  assert_eq(
    publication_snapshot_evidence_cid(observed),
    Some(
      "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ),
  )
  expect_snapshot_issue(None, IndexQueryUnknown, IndexObservationUnknown)
  expect_snapshot_issue(
    Some(unknown),
    IndexQueryUnknown,
    IndexObservationUnknown,
  )
  expect_snapshot_issue(
    Some(runtime_record("succeeded", 2L)),
    IndexConfirmedAbsent,
    ContradictoryRecord,
  )
}

///|
test "publication snapshot binds a committed index to its attempt" {
  let index_cid = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let attempt_cid = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let index = snapshot_index_entry(attempt_cid, index_cid)
  let committing = runtime_record("committing", 1L)
  let observed = project_publication_snapshot(
    Some(committing),
    IndexCommitted(index),
  ).unwrap()
  assert_eq(publication_snapshot_state(observed), Succeeded)
  assert_eq(publication_snapshot_evidence_cid(observed), Some(index_cid))
  expect_snapshot_issue(None, IndexCommitted(index), MissingRecord)
  expect_snapshot_issue(
    Some(committing),
    IndexCommitted(
      snapshot_index_entry(
        "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        index_cid,
      ),
    ),
    AttemptMismatch,
  )
  expect_snapshot_issue(
    Some(runtime_record("failed", 2L)),
    IndexCommitted(index),
    ContradictoryRecord,
  )
}
