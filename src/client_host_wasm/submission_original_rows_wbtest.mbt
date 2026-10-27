///|
fn original_rows_identity(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
) -> (@host.ClientRequestIdentity, @publication.PublicationContract) {
  for (table, row) in rows {
    if table == "client_runs" {
      let run = @host.decode_client_run_journal_row(row.body).unwrap()
      return (run.request, run.definition)
    }
  }
  abort("missing original Run fixture")
}

///|
fn original_row_fields(
  row : @host.ClientJournalPhysicalRow,
) -> (String, Int64, Bytes) {
  (row.key, row.revision, row.body)
}

///|
test "completed original data avoids repeated full nested validator and keeps fresh rows cancellation" {
  let rows = targeted_snapshot_rows()
  let mut initial_completed = 0
  let submission = @host.decode_client_submitted_journal_row(
    @utf8.encode(targeted_submission_ready),
  ).unwrap()
  let original = @host.read_client_saved_submission(
      submission.reference,
      (table, key) => targeted_row_read(rows, table, key),
      row => {
        let result = submission_append_run_inspection(row)
        if result is Ok(_) {
          initial_completed += 1
        }
        result
      },
      -31,
    )
    .unwrap()
    .unwrap()
  let mut completed_reads = 0
  let mut completed_nested = 0
  let mut completed_cancel = 0
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
            completed_reads += 1
          }
          result
        },
        row => {
          let result = submission_append_run_inspection(row)
          if result is Ok(_) {
            completed_nested += 1
          }
          result
        },
        () => {
          let result = @host.inspect_client_empty_cancellation_inventory(
            1024,
            (table, cursor) => targeted_row_scan(rows, table, cursor),
            (table, key) => targeted_row_read(rows, table, key),
            -31,
            -42,
          )
          if result is Ok(_) {
            completed_cancel += 1
          }
          result
        },
        original_identity=Some(original_rows_identity(rows)),
      )
      .unwrap()
      .unwrap()
    assert_eq(
      original_row_fields(@host.client_saved_submission_row(actual)),
      original_row_fields(@host.client_saved_submission_row(original)),
    )
    assert_eq(
      original_row_fields(
        @host.client_saved_submission_run_row(actual).unwrap(),
      ),
      original_row_fields(
        @host.client_saved_submission_run_row(original).unwrap(),
      ),
    )
  }
  assert_eq(initial_completed, 1)
  assert_eq(completed_reads, 4)
  assert_eq(completed_nested, 0)
  assert_eq(completed_cancel, 2)
  println(
    "ACTQL_ORIGINAL_ROWS_WORK completed_initial_nested=1 completed_repeated_nested=0 completed_target_reads=4 completed_cancel_validators=2",
  )
}

///|
test "changed and absent original proofs take full nested path with original cancellation order" {
  let rows = targeted_snapshot_rows()
  let original = targeted_original(rows)
  let identity = original_rows_identity(rows)
  for table in ["client_submitted_intents", "client_runs"] {
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
    let mut completed_nested = 0
    let mut completed_cancel = 0
    assert_true(
      submission_run_reference_snapshot(
        "scope",
        "sha256:" + "b".repeat(64),
        "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
        Some(original),
        (_, _) => Err(-99),
        (name, key) => targeted_row_read(changed, name, key),
        row => {
          let result = submission_append_run_inspection(row)
          if result is Ok(_) {
            completed_nested += 1
          }
          result
        },
        () => {
          completed_cancel += 1
          Ok(())
        },
        original_identity=Some(identity),
      )
      is Err(-32),
    )
    assert_eq(completed_nested, 1)
    assert_eq(completed_cancel, 1)
  }
  let missing = rows.filter(pair => pair.0 != "client_submitted_intents")
  assert_true(
    submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (name, key) => targeted_row_read(missing, name, key),
      _ => Err(-98),
      () => Err(-97),
      original_identity=Some(identity),
    )
    is Err(-97),
  )
  // Without the completed source identity, even byte-exact rows run the
  // original full validator. A generic Snapshot cannot select this route.
  assert_true(
    submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (name, key) => targeted_row_read(rows, name, key),
      _ => Err(-98),
      () => Ok(()),
    )
    is Err(-98),
  )
}

///|
test "original data never repairs corrupt nested rows or replaces current cancellation and query refusal" {
  let rows = targeted_snapshot_rows()
  let original = targeted_original(rows)
  let identity = original_rows_identity(rows)
  let corrupt = rows.map(pair => {
    let (name, row) = pair
    (name, if name == "client_runs" { { ..row, body: b"{}", } } else { row })
  })
  let mut cancelled = false
  assert_true(
    submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (name, key) => targeted_row_read(corrupt, name, key),
      submission_append_run_inspection,
      () => {
        cancelled = true
        Ok(())
      },
      original_identity=Some(identity),
    )
    is Err(-31),
  )
  assert_false(cancelled)
  assert_true(
    submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (name, key) => targeted_row_read(rows, name, key),
      _ => Err(-98),
      () => Err(-97),
      original_identity=Some(identity),
    )
    is Err(-97),
  )
  assert_true(
    submission_run_reference_snapshot(
      "scope",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (_, _) => Err(-96),
      _ => Err(-98),
      () => Err(-97),
      original_identity=Some(identity),
    )
    is Err(-96),
  )
  let mut completed_full = 0
  assert_true(
    submission_run_reference_snapshot(
      "foreign",
      "sha256:" + "b".repeat(64),
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      Some(original),
      (_, _) => Err(-99),
      (name, key) => targeted_row_read(rows, name, key),
      row => {
        let result = submission_append_run_inspection(row)
        if result is Ok(_) {
          completed_full += 1
        }
        result
      },
      () => Ok(()),
      original_identity=Some(identity),
    )
    is Err(-32),
  )
  assert_eq(completed_full, 1)
}
