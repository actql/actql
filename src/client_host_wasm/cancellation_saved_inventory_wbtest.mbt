///|
// Fixed physical rows exercise the actual shared Saved/cancellation callee.
// No physical Host import, authentication, write, stop or ACK is supplied.
fn cancellation_saved_rows() -> Array[(String, @host.ClientJournalPhysicalRow)] {
  let rows = targeted_snapshot_rows()
  let original = original_rows_identity(rows)
  let identity = @host.prepare_client_cancellation_identity(
    "scope",
    @host.client_request_authority_scope_cid(original.0),
    "saved-cancel",
    original.1,
    19,
  ).unwrap()
  let body = @host.client_cancellation_journal_row_body({
    namespace_id: "scope",
    cancel_id: "saved-cancel",
    expected_revision: 19,
    request: original.0,
    definition: original.1,
    identity,
    action: @host.AlreadyTerminal,
    observed_revision: 19L,
  }).unwrap()
  let key = @host.client_cancellation_journal_index(
    "scope",
    @host.client_request_authority_scope_cid(original.0),
    "saved-cancel",
  ).unwrap()
  let actual = rows.map(pair => {
    if pair.0 == "client_cancel_custody" {
      (pair.0, { key: "issued", revision: 1L, body: b"1", })
    } else {
      pair
    }
  })
  actual.push(("client_cancellations", { key, revision: 0L, body, }))
  actual.push(
    (
      "client_cancel_originals",
      { key, revision: 0L, body: @utf8.encode(@sha.hex(body)), },
    ),
  )
  actual
}

///|
fn cancellation_saved_observe(
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
      submission_cancellation_inventory(
        (table, cursor) => targeted_row_scan(rows, table, cursor),
        (table, key) => targeted_row_read(rows, table, key),
      )
    },
  )
}

///|
test "Saved source retains complete original rows with valid nonempty cancellation history" {
  let rows = cancellation_saved_rows()
  let original = targeted_original(rows)
  for saved in [None, Some(original)] {
    guard cancellation_saved_observe(rows, saved) is Ok(Some(actual)) else {
      fail("valid original Saved rows refused")
    }
    assert_eq(
      original_row_fields(@host.client_saved_submission_row(actual)),
      original_row_fields(@host.client_saved_submission_row(original)),
    )
    assert_eq(
      @host.client_saved_submission_run_row(actual).map(original_row_fields),
      @host.client_saved_submission_run_row(original).map(original_row_fields),
    )
  }
}

///|
test "completed Saved cannot bypass missing cancellation witness or physical query failure" {
  let rows = cancellation_saved_rows()
  let original = targeted_original(rows)
  assert_true(
    cancellation_saved_observe(
      rows.filter(pair => pair.0 != "client_cancel_originals"),
      Some(original),
    )
    is Err(-31),
  )
  assert_eq(
    submission_cancellation_inventory(
      (table, cursor) => targeted_row_scan(rows, table, cursor),
      (table, key) => {
        if table == "client_cancel_originals" {
          Err(-41)
        } else {
          targeted_row_read(rows, table, key)
        }
      },
    ),
    Err(-41),
  )
}

///|
test "nonempty cancellation retains the full existing nested Run validation frontier" {
  let rows = cancellation_saved_rows().map(pair => {
    let (table, row) = pair
    if table == "client_runs" {
      let run = @host.decode_client_run_journal_row(row.body).unwrap()
      (
        table,
        {
          ..row,
          body: @host.client_run_journal_row_body({
            ..run,
            checkpoint: Some("{}"),
          }).unwrap(),
        },
      )
    } else {
      pair
    }
  })
  assert_eq(
    submission_cancellation_inventory(
      (table, cursor) => targeted_row_scan(rows, table, cursor),
      (table, key) => targeted_row_read(rows, table, key),
    ),
    Err(-42),
  )
}
