///|
// Fixed independent submitted-row schema/identity fixture from the existing
// Common vectors. Its epoch is shape DATA, not physical authentication.
let targeted_submission_ready : String =
  #|{"intent":"{\"input\":{\"format\":\"sql\",\"text\":\"/*😀*/\\r\\nSELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":{\"é/~\":null,\"é\":{\"missing\":{}}}}","phase":"ready","reference":"{\"epoch\":{\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"authorityScopeCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"expiresAt\":2000,\"notBefore\":1000,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-submit\"}","run_admission":"{\"admitted_revision\":\"9007199254740993\",\"request\":\"{\\\"authority_scope_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"run_definition_cid\":\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\"}","version":"actql-native-client-submitted-intent-row/0.1"}

///|
fn targeted_snapshot_rows() -> Array[(String, @host.ClientJournalPhysicalRow)] {
  let submission = @host.decode_client_submitted_journal_row(
    @utf8.encode(targeted_submission_ready),
  ).unwrap()
  let request = submission.run_admission.unwrap().0
  let base = @host.decode_client_run_journal_row(
    @utf8.encode(submission_identity_wire),
  ).unwrap()
  let body = @host.client_run_journal_row_body({ ..base, request, }).unwrap()
  [
    ("client_run_custody", { key: "issued", revision: 0L, body: b"1", }),
    (
      "client_submitted_intent_custody",
      { key: "issued", revision: 0L, body: b"1", },
    ),
    ("client_cancel_custody", { key: "issued", revision: 0L, body: b"0", }),
    (
      "client_submitted_intents",
      {
        key: @host.client_submission_reference_record_request_id(
          submission.reference,
        ),
        revision: 6L,
        body: @utf8.encode(targeted_submission_ready),
      },
    ),
    (
      "client_runs",
      {
        key: @host.client_request_scope_cid(request),
        revision: 9007199254740994L,
        body,
      },
    ),
  ]
}

///|
fn targeted_row_read(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  table : String,
  key : String,
) -> Result[@host.ClientJournalPhysicalRow?, Int] {
  for (name, row) in rows {
    if name == table && row.key == key {
      return Ok(Some(row))
    }
  }
  Ok(None)
}

///|
fn targeted_row_scan(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  table : String,
  cursor : String,
) -> Result[@host.ClientJournalPhysicalRow?, Int] {
  let mut selected : @host.ClientJournalPhysicalRow? = None
  for (name, row) in rows {
    if name == table &&
      row.key > cursor &&
      (selected is None || row.key < selected.unwrap().key) {
      selected = Some(row)
    }
  }
  Ok(selected)
}

///|
fn targeted_original(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
) -> @host.ClientSavedSubmissionSnapshot {
  let submission = @host.decode_client_submitted_journal_row(
    @utf8.encode(targeted_submission_ready),
  ).unwrap()
  @host.read_client_saved_submission(
    submission.reference,
    (table, key) => targeted_row_read(rows, table, key),
    submission_append_run_inspection,
    -31,
  )
  .unwrap()
  .unwrap()
}

///|
fn targeted_observe(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  original : @host.ClientSavedSubmissionSnapshot?,
) -> Result[@host.ClientSavedSubmissionSnapshot?, Int] {
  submission_run_reference_snapshot(
    "scope",
    "sha256:" + "b".repeat(64),
    "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
    original,
    (table, cursor) => targeted_row_scan(rows, table, cursor),
    (table, key) => targeted_row_read(rows, table, key),
    submission_append_run_inspection,
    () => {
      @host.inspect_client_empty_cancellation_inventory(
        1024,
        (table, cursor) => targeted_row_scan(rows, table, cursor),
        (table, key) => targeted_row_read(rows, table, key),
        -31,
        -42,
      )
    },
  )
}

///|
test "completed saved holder freshly reads two original rows and keeps cancellation checks" {
  let rows = targeted_snapshot_rows()
  let original = targeted_observe(rows, None).unwrap().unwrap()
  let reads : Array[String] = []
  let scans : Array[String] = []
  let mut nested = 0
  for _ in 0..<2 {
    let actual = submission_run_reference_snapshot(
        "scope",
        "sha256:" + "b".repeat(64),
        "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
        Some(original),
        (_, _) => Err(-99),
        (table, key) => {
          let result = targeted_row_read(rows, table, key)
          if result is Ok(_) {
            reads.push(table)
          }
          result
        },
        row => {
          let result = submission_append_run_inspection(row)
          if result is Ok(_) {
            nested += 1
          }
          result
        },
        () => {
          @host.inspect_client_empty_cancellation_inventory(
            1024,
            (table, cursor) => {
              let result = targeted_row_scan(rows, table, cursor)
              if result is Ok(_) {
                scans.push(table)
              }
              result
            },
            (table, key) => {
              let result = targeted_row_read(rows, table, key)
              if result is Ok(_) {
                reads.push(table)
              }
              result
            },
            -31,
            -42,
          )
        },
      )
      .unwrap()
      .unwrap()
    assert_eq(
      @host.client_saved_submission_row(actual).body,
      @host.client_saved_submission_row(original).body,
    )
    assert_eq(
      @host.client_saved_submission_run_row(actual).unwrap().body,
      @host.client_saved_submission_run_row(original).unwrap().body,
    )
  }
  assert_eq(reads, [
    "client_submitted_intents", "client_runs", "client_cancel_custody", "client_submitted_intents",
    "client_runs", "client_cancel_custody",
  ])
  assert_eq(scans, [
    "client_cancel_custody", "client_cancel_custody", "client_cancellations", "client_cancel_originals",
    "client_cancel_custody", "client_cancel_custody", "client_cancellations", "client_cancel_originals",
  ])
  assert_eq(nested, 2)
  println(
    "ACTQL_SAME_HOLDER_WORK calls=2 completed_target_reads=4 completed_cancel_queries=10 completed_nested_validators=2 unrelated_payload_queries=0",
  )
}

///|
test "initial admission retains full history while completed selection ignores unrelated payload" {
  let rows = targeted_snapshot_rows()
  let original = targeted_original(rows)
  rows.push(
    (
      "client_runs",
      { key: "unrelated", revision: 0L, body: b"corrupt-unrelated", },
    ),
  )
  assert_true(targeted_observe(rows, None) is Err(-31))
  assert_true(targeted_observe(rows, Some(original)) is Ok(Some(_)))
  // Every target observation is still fresh, including a transport failure.
  assert_true(
    submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (_, _) => Err(-98),
      submission_append_run_inspection,
      () => Ok(()),
    )
    is Err(-98),
  )
}

///|
test "retained selection refuses changed missing and invalid nested target rows" {
  let rows = targeted_snapshot_rows()
  let original = targeted_original(rows)
  for table in ["client_runs", "client_submitted_intents"] {
    let changed = rows.map(pair => {
      let (name, row) = pair
      (
        name,
        if name == table {
          { ..row, revision: row.revision + 1L, }
        } else {
          row
        },
      )
    })
    assert_true(targeted_observe(changed, Some(original)) is Err(-32))
    let missing = rows.filter(pair => pair.0 != table)
    if table == "client_runs" {
      assert_true(targeted_observe(missing, Some(original)) is Err(-31))
    } else {
      assert_true(targeted_observe(missing, Some(original)) is Ok(None))
    }
  }
  let corrupt = rows.map(pair => {
    let (name, row) = pair
    (name, if name == "client_runs" { { ..row, body: b"{}", } } else { row })
  })
  assert_true(targeted_observe(corrupt, Some(original)) is Err(-31))
  let policy = rows.map(pair => {
    let (name, row) = pair
    if name != "client_runs" {
      return (name, row)
    }
    let record = @host.decode_client_run_journal_row(row.body).unwrap()
    (
      name,
      {
        ..row,
        body: @host.client_run_journal_row_body(
          record,
          local_run_policy_originals=Some("{}"),
        ).unwrap(),
      },
    )
  })
  assert_true(targeted_observe(policy, Some(original)) is Err(-31))
}

///|
test "retained selection keeps exact scope definition and cancellation refusal" {
  let rows = targeted_snapshot_rows()
  let original = targeted_original(rows)
  for
    (namespace, scope, definition) in [
      (
        "foreign",
        "sha256:" + "b".repeat(64),
        "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      ),
      (
        "scope",
        "sha256:" + "a".repeat(64),
        "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      ),
      ("scope", "sha256:" + "b".repeat(64), "sha256:" + "1".repeat(64)),
    ] {
    assert_true(
      submission_run_reference_snapshot(
        namespace,
        scope,
        definition,
        Some(original),
        (table, cursor) => targeted_row_scan(rows, table, cursor),
        (table, key) => targeted_row_read(rows, table, key),
        submission_append_run_inspection,
        () => Ok(()),
      )
      is Err(-32),
    )
  }
  let missing = rows.filter(pair => pair.0 != "client_cancel_custody")
  assert_true(targeted_observe(missing, Some(original)) is Err(-31))
  let active = rows.map(pair => {
    let (name, row) = pair
    (
      name,
      if name == "client_cancel_custody" {
        { ..row, revision: 1L, body: b"1", }
      } else {
        row
      },
    )
  })
  assert_true(targeted_observe(active, Some(original)) is Err(-42))
  rows.push(
    (
      "client_cancel_originals",
      { key: "unexpected", revision: 0L, body: b"{}", },
    ),
  )
  assert_true(targeted_observe(rows, Some(original)) is Err(-31))
}

///|
test "missing selected submission still observes cancellation before absence" {
  let original = targeted_original(targeted_snapshot_rows())
  let mut reads = 0
  let mut cancellations = 0
  for issue in [None, Some(-41), Some(-42)] {
    let result = submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (table, _) => {
        if table != "client_submitted_intents" {
          return Err(-99)
        }
        reads += 1
        Ok(None)
      },
      _ => Err(-99),
      () => {
        cancellations += 1
        match issue {
          None => Ok(())
          Some(code) => Err(code)
        }
      },
    )
    match issue {
      None => assert_true(result is Ok(None))
      Some(code) => assert_true(result is Err(actual) && actual == code)
    }
  }
  assert_eq(reads, 3)
  assert_eq(cancellations, 3)
}

///|
test "indexed saved cold lookup selects exact original without unrelated Run audit" {
  let rows = targeted_snapshot_rows()
  let ready = @host.decode_client_submitted_journal_row(
    @utf8.encode(targeted_submission_ready),
  ).unwrap()
  let run = submission_append_run_inspection(
    targeted_row_read(
      rows,
      "client_runs",
      @host.client_request_scope_cid(ready.run_admission.unwrap().0),
    ).unwrap().unwrap(),
  ).unwrap()
  let (key, body) = @host.client_saved_run_reference_locator(
    ready.reference, run.request, run.definition,
  ).unwrap()
  rows.push(("client_run_reference_index", { key, body, revision: 0L, }))
  // Unrelated integrity inspection is not a selected read of this original.
  rows.push(("client_runs", { key: "unrelated", body: b"invalid", revision: 0L, }))
  let reads : Array[String] = []
  let mut nested = 0
  let mut cancellation = 0
  let actual = submission_run_reference_snapshot(
    "scope",
    "sha256:" + "b".repeat(64),
    "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
    None,
    (_, _) => Err(-88),
    (table, selected) => {
      reads.push(table)
      targeted_row_read(rows, table, selected)
    },
    row => {
      nested += 1
      submission_append_run_inspection(row)
    },
    () => {
      cancellation += 1
      Ok(())
    },
    physical_schema=1,
  )
  guard actual is Ok(Some(snapshot)) else { fail("selected original refused") }
  assert_eq(
    @host.client_submission_reference_record_wire(
      @host.client_saved_submission_record(snapshot).reference,
    ),
    @host.client_submission_reference_record_wire(ready.reference),
  )
  assert_eq(reads, ["client_run_reference_index", "client_submitted_intents", "client_runs"])
  assert_eq(nested, 1)
  assert_eq(cancellation, 1)
}
