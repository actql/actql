///|
// The response is fixed independently from the original schema fixtures.
// These callbacks establish no physical durability or current authorization.
let saved_admission_public_wire : String =
  #|{"ref":{"namespaceId":"scope","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","runDefinitionCid":"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc"},"durability":"durable","revision":0}

///|
fn public_admission_snapshot(
  revision : String,
) -> ClientSavedSubmissionSnapshot {
  let body = saved_submission_ready.replace(
    old="9007199254740993",
    new=revision,
  )
  saved_snapshot_inspect(saved_snapshot_rows(body)).unwrap().unwrap()
}

///|
test "saved public admission uses original definition scope and admitted revision" {
  let snapshot = public_admission_snapshot("0")
  assert_eq(
    client_saved_submission_admission_wire(snapshot).unwrap(),
    saved_admission_public_wire,
  )
  assert_eq(
    client_saved_submission_run_row(snapshot).unwrap().revision,
    9007199254740994L,
  )
  assert_eq(client_saved_submission_revision(snapshot), 6L)
}

///|
test "saved public admission preserves maximal safe revision and refuses rounding" {
  assert_eq(
    client_saved_submission_admission_wire(
      public_admission_snapshot("9007199254740991"),
    ).unwrap(),
    saved_admission_public_wire.replace(
      old="\"revision\":0",
      new="\"revision\":9007199254740991",
    ),
  )
  for revision in ["9007199254740992", "9007199254740993"] {
    let snapshot = public_admission_snapshot(revision)
    assert_eq(
      client_saved_submission_admission_wire(snapshot),
      Err(UnrepresentableRevision),
    )
    assert_eq(snapshot.record.run_admission.unwrap().2.to_string(), revision)
  }
}

///|
test "preparing observation cannot acquire a public Run admission" {
  let snapshot = read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => {
        inventory_read(
          saved_snapshot_rows(saved_submission_preparing),
          table,
          key,
        )
      },
      _ => Err("unexpected Run validation"),
      "custody",
    )
    .unwrap()
    .unwrap()
  assert_eq(client_saved_submission_admission_wire(snapshot), Err(NotAdmitted))
}

///|
test "public admission cannot replace original validated Run or scope" {
  let snapshot = public_admission_snapshot("0")
  let changed : ClientRunJournalInspection = {
    ..snapshot.inspection.unwrap(),
    request: admit_client_request_identity_record_wire(
      saved_submission_scope_request,
    ).unwrap(),
  }
  assert_eq(
    client_saved_submission_admission_wire({
      ..snapshot,
      inspection: Some(changed),
    }),
    Err(CustodyLost),
  )
  assert_eq(
    client_saved_submission_admission_wire({ ..snapshot, inspection: None, }),
    Err(CustodyLost),
  )
  assert_eq(
    client_saved_submission_admission_wire({ ..snapshot, run: None, }),
    Err(CustodyLost),
  )
}

///|
// New independent namespace fixtures; the historical fixed bodies stay intact.
// The existing seal/retained-row Owners establish identity, never this view.
fn namespace_admission_snapshot(
  run_namespace : String,
) -> ClientSavedSubmissionSnapshot {
  let definition = @publication.seal_publication_contract(
    "run_definition",
    journal_encoding_definition
    .replace(
      old="\"run_definition_cid\":\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\",",
      new="",
    )
    .replace(
      old="\"scope_id\":\"scope\"",
      new="\"scope_id\":\"" + run_namespace + "\"",
    ),
    65536,
    4096,
    64,
  ).unwrap()
  let body = saved_submission_ready
    .replace(old="9007199254740993", new="0")
    .replace(
      old="sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      new=@publication.publication_contract_identity(definition),
    )
  let rows = saved_snapshot_rows(body)
  inspect_client_saved_submission(
    saved_snapshot_reference(),
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    _ => Ok({ ..saved_snapshot_run(), definition, }),
    () => Ok(()),
    "custody",
  )
  .unwrap()
  .unwrap()
}

///|
test "saved admission namespace projection uses the public UTF16 bound without changing originals" {
  for
    (run_namespace, admitted) in [
      ("😀".repeat(128), true),
      ("😀".repeat(129), false),
      ("a".repeat(256), true),
      ("a".repeat(257), false),
    ] {
    let snapshot = namespace_admission_snapshot(run_namespace)
    let record = client_saved_submission_record(snapshot)
    let row = client_saved_submission_row(snapshot)
    let run = client_saved_submission_run_row(snapshot).unwrap()
    let definition = snapshot.inspection.unwrap().definition
    let result = client_saved_submission_admission_wire(snapshot)
    if admitted {
      assert_true(
        result.unwrap().contains("\"namespaceId\":\"" + run_namespace + "\""),
      )
    } else {
      assert_eq(result, Err(Encoding))
    }
    assert_eq(
      @publication.run_definition_namespace(definition),
      Some(run_namespace),
    )
    assert_eq(
      client_submitted_intent_wire(
        client_saved_submission_record(snapshot).intent,
      ),
      client_submitted_intent_wire(record.intent),
    )
    assert_eq(client_saved_submission_row(snapshot).body, row.body)
    assert_eq(client_saved_submission_row(snapshot).revision, row.revision)
    assert_eq(client_saved_submission_run_row(snapshot).unwrap().body, run.body)
    assert_eq(
      client_saved_submission_run_row(snapshot).unwrap().revision,
      run.revision,
    )
    assert_eq(
      record.run_admission.unwrap().1,
      @publication.publication_contract_identity(definition),
    )
    assert_eq(record.run_admission.unwrap().2, 0L)
  }
}

///|
test "accepted failure candidate preserves same intent and refuses terminal or foreign originals" {
  let rows = saved_snapshot_rows(saved_submission_preparing)
  let snapshot = read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("must-not-validate-Run"),
      "custody",
    )
    .unwrap()
    .unwrap()
  let expected = saved_submission_preparing.replace(
    old="\"phase\":\"preparing\",\"reference\":",
    new="\"phase\":\"preparation_failed\",\"preparation_problem_classification\":\"invalid_input\",\"preparation_problem_code\":\"ClientProgramInvalidInput\",\"reference\":",
  )
  assert_eq(
    client_saved_submission_preparation_failure_body(
      snapshot,
      snapshot.record.intent,
      ("ClientProgramInvalidInput", "invalid_input"),
    ),
    Ok(@utf8.encode(expected)),
  )
  let changed = prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 2 AS n\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  assert_eq(
    client_saved_submission_preparation_failure_body(
      snapshot,
      changed,
      ("ClientProgramInvalidInput", "invalid_input"),
    ),
    Err(CustodyLost),
  )
  let terminal = decode_client_submitted_journal_row(@utf8.encode(expected)).unwrap()
  assert_eq(
    client_saved_submission_preparation_failure_body(
      { ..snapshot, record: terminal, },
      terminal.intent,
      ("OtherFailure", "operation_failed"),
    ),
    Err(CustodyLost),
  )
  let ready = public_admission_snapshot("0")
  assert_eq(
    client_saved_submission_preparation_failure_body(
      ready,
      ready.record.intent,
      ("OtherFailure", "operation_failed"),
    ),
    Err(CustodyLost),
  )
  assert_eq(
    client_saved_submission_preparation_failure_body(
      snapshot,
      snapshot.record.intent,
      ("", "invalid_input"),
    ),
    Err(Encoding),
  )
}
