///|
// The response is fixed independently from the original schema fixtures.
// These callbacks establish no physical durability or current authorization.
let saved_admission_public_wire : String =
  #|{"ref":{"namespaceId":"scope","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runDefinitionCid":"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc"},"durability":"durable","revision":0}

///|
fn public_admission_snapshot(revision : String) -> ClientSavedSubmissionSnapshot {
  let body = saved_submission_ready.replace(old="9007199254740993", new=revision)
  saved_snapshot_inspect(saved_snapshot_rows(body)).unwrap().unwrap()
}

///|
test "saved public admission uses original definition scope and admitted revision" {
  let snapshot = public_admission_snapshot("0")
  assert_eq(client_saved_submission_admission_wire(snapshot).unwrap(), saved_admission_public_wire)
  assert_eq(client_saved_submission_run_row(snapshot).unwrap().revision, 9007199254740994L)
  assert_eq(client_saved_submission_revision(snapshot), 6L)
}

///|
test "saved public admission preserves maximal safe revision and refuses rounding" {
  assert_eq(
    client_saved_submission_admission_wire(public_admission_snapshot("9007199254740991")).unwrap(),
    saved_admission_public_wire.replace(old="\"revision\":0", new="\"revision\":9007199254740991"),
  )
  for revision in ["9007199254740992", "9007199254740993"] {
    let snapshot = public_admission_snapshot(revision)
    assert_eq(client_saved_submission_admission_wire(snapshot), Err(UnrepresentableRevision))
    assert_eq(snapshot.record.run_admission.unwrap().2.to_string(), revision)
  }
}

///|
test "preparing observation cannot acquire a public Run admission" {
  let snapshot = read_client_saved_submission(
    saved_snapshot_reference(),
    (table, key) => inventory_read(saved_snapshot_rows(saved_submission_preparing), table, key),
    _ => Err("unexpected Run validation"),
    "custody",
  ).unwrap().unwrap()
  assert_eq(client_saved_submission_admission_wire(snapshot), Err(NotAdmitted))
}

///|
test "public admission cannot replace original validated Run or scope" {
  let snapshot = public_admission_snapshot("0")
  let changed : ClientRunJournalInspection = {
    ..snapshot.inspection.unwrap(),
    request: admit_client_request_identity_record_wire(saved_submission_scope_request).unwrap(),
  }
  assert_eq(client_saved_submission_admission_wire({ ..snapshot, inspection: Some(changed), }), Err(CustodyLost))
  assert_eq(client_saved_submission_admission_wire({ ..snapshot, inspection: None, }), Err(CustodyLost))
  assert_eq(client_saved_submission_admission_wire({ ..snapshot, run: None, }), Err(CustodyLost))
}
