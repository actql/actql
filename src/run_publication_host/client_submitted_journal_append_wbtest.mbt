///|
let append_request_id : String = "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267"

///|
fn append_original_record() -> ClientSubmittedJournalEncoding {
  decode_client_submitted_journal_row(@utf8.encode(saved_submission_preparing)).unwrap()
}

///|
fn append_plan(
  rows : Array[(String, ClientJournalPhysicalRow)],
  intent? : ClientSubmittedIntent = append_original_record().intent,
  validity? : SubmissionEpochValidity = @request_scope.Admissible,
  max_records? : Int = 1024,
) -> Result[
  ClientSubmittedJournalAppendPlan,
  ClientSubmittedJournalAppendIssue[String],
] {
  prepare_client_submitted_journal_append(
    append_original_record().reference,
    intent,
    validity,
    max_records,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    row => decode_client_submitted_journal_row(row.body).map_err(_ => "custody"),
    _ => Err("unexpected-Run-validation"),
    "custody",
  )
}

///|
test "fresh original preparing append preserves fixed row and issued CAS without Run" {
  let rows = [
    (
      "client_submitted_intent_custody",
      inventory_row("issued", b"0", revision=17L),
    ),
  ]
  guard append_plan(rows) is Ok(Append(plan)) else { fail("missing append") }
  let (key, body, revision, count) = client_submitted_journal_append_rows(plan)
  assert_eq(key, append_request_id)
  assert_eq(body, @utf8.encode(saved_submission_preparing))
  assert_eq(revision, 17L)
  assert_eq(count, b"1")
}

///|
test "retained preparing identity survives expiry without a new candidate" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    (
      "client_submitted_intents",
      inventory_row(
        append_request_id,
        @utf8.encode(saved_submission_preparing),
        revision=6L,
      ),
    ),
  ]
  guard append_plan(rows, validity=@request_scope.Expired)
    is Ok(Retained(snapshot)) else {
    fail("retained original rejected")
  }
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_true(client_saved_submission_record(snapshot).run_admission is None)
}

///|
test "changed intent cannot replace original preparing row" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    (
      "client_submitted_intents",
      inventory_row(append_request_id, @utf8.encode(saved_submission_preparing)),
    ),
  ]
  let changed = prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 2 AS n\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  assert_true(append_plan(rows, intent=changed) is Err(ChangedIntent))
}

///|
test "missing custody and partial inventory cannot issue append" {
  assert_true(append_plan([]) is Err(Observation("custody")))
  assert_true(
    append_plan([
      ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    ])
    is Err(Observation("custody")),
  )
}

///|
test "missing original after epoch expiry is not insertion or resend permission" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"0")),
  ]
  assert_true(
    append_plan(rows, validity=@request_scope.Expired)
    is Err(EpochRejected(@request_scope.Expired)),
  )
  assert_true(
    append_plan(rows, validity=@request_scope.NotYetValid)
    is Err(EpochRejected(@request_scope.NotYetValid)),
  )
}

///|
test "query failure remains observation error rather than missing original" {
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"0")),
  ]
  let result = prepare_client_submitted_journal_append(
    append_original_record().reference,
    append_original_record().intent,
    @request_scope.Admissible,
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => {
      if table == "client_submitted_intents" {
        Err("query-failure")
      } else {
        inventory_read(rows, table, key)
      }
    },
    row => decode_client_submitted_journal_row(row.body).map_err(_ => "custody"),
    _ => Err("unexpected-Run-validation"),
    "custody",
  )
  assert_true(result is Err(Observation("query-failure")))
}

///|
test "full inventory refuses a different fresh reference but preserves retained ready identity" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let reference = append_original_record().reference
  let decide = reference => {
    prepare_client_submitted_journal_append(
      reference,
      append_original_record().intent,
      @request_scope.Admissible,
      1,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      row => {
        decode_client_submitted_journal_row(row.body).map_err(_ => "custody")
      },
      _ => Ok(saved_snapshot_run()),
      "custody",
    )
  }
  guard decide(reference) is Ok(Retained(snapshot)) else {
    fail("retained ready original must not append")
  }
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(
    client_saved_submission_record(snapshot).run_admission.unwrap().2,
    9007199254740993L,
  )
  let another = prepare_client_submission_reference_record(
    client_submission_reference_record_epoch(reference),
    "other-submission",
  ).unwrap()
  assert_true(decide(another) is Err(CapacityExceeded))
}

///|
test "selected nested Run validator failure is preserved without validating unrelated submissions" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let later_validations : Array[Int] = []
  let result = prepare_client_submitted_journal_append(
    append_original_record().reference,
    append_original_record().intent,
    @request_scope.Admissible,
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    _ => Err("original-validator-failure"),
    _ => {
      later_validations.push(1)
      Err("selected-original-validator-failure")
    },
    "custody",
  )
  assert_true(result is Err(Observation("selected-original-validator-failure")))
  assert_eq(later_validations, [1])
}

///|
test "retained submission target does not scan unrelated Run or Effect history" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let calls : Array[String] = []
  let result = prepare_client_submitted_journal_append(
    append_original_record().reference,
    append_original_record().intent,
    @request_scope.Expired,
    1024,
    (table, _) => {
      calls.push("scan:" + table)
      Err("unexpected-inventory")
    },
    (table, key) => {
      calls.push("read:" + table + ":" + key)
      inventory_read(rows, table, key)
    },
    _ => Err("unexpected-submission-inventory"),
    _ => {
      calls.push("validate-selected-run")
      Ok(saved_snapshot_run())
    },
    "custody",
  )
  guard result is Ok(Retained(snapshot)) else {
    fail("selected original refused")
  }
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(calls.filter(value => value.has_prefix("scan:")).length(), 0)
  assert_eq(calls.filter(value => value == "validate-selected-run").length(), 1)
  assert_eq(
    calls.filter(value => value.has_prefix("read:client_runs:")).length(),
    1,
  )
  assert_eq(
    calls
    .filter(value => value.has_prefix("read:client_submitted_intents:"))
    .length(),
    1,
  )
}
