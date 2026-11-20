///|
// Explicit same-call physical ports and canonical constructors. No current,
// Store, Run authority, normal runtime or physical cleanup ACK is supplied.
test "scanned submission exact row uses one canonical decode and fresh point read" {
  let rows = saved_snapshot_rows(saved_submission_preparing)
  let scanned = rows[3].1
  let phases = Ref(0)
  let reads : Array[String] = []
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  let snapshot = read_client_scanned_submission_with_task_original(
    scanned,
    (table, key) => {
      reads.push(table + ":" + key)
      inventory_read(rows, table, key)
    },
    _ => Err("unexpected-run-validator"),
    "custody",
    original,
    before_construction=Some(_ => {
      phases.val += 1
      Ok(())
    }),
  ).unwrap()
  assert_eq(phases.val, 2) // One Parse and one Canonical construction.
  assert_eq(reads, ["client_submitted_intents:" + scanned.key])
  assert_true(physical_equal(client_saved_submission_row(snapshot), scanned))
  assert_true(client_saved_submission_record(snapshot).run_admission is None)
  assert_eq(
    client_saved_submission_row(snapshot).body,
    @utf8.encode(saved_submission_preparing),
  )
}

///|
test "scanned ready row retains original Run validation and failure ordering" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let scanned = rows[3].1
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  let phases = Ref(0)
  let reads : Array[String] = []
  let validators = Ref(0)
  let snapshot = read_client_scanned_submission_with_task_original(
    scanned,
    (table, key) => {
      reads.push(table)
      inventory_read(rows, table, key)
    },
    _ => {
      validators.val += 1
      Ok(saved_snapshot_run())
    },
    "custody",
    original,
    before_construction=Some(_ => {
      phases.val += 1
      Ok(())
    }),
  ).unwrap()
  assert_eq(phases.val, 2)
  assert_eq(reads, ["client_submitted_intents", "client_runs"])
  assert_eq(validators.val, 1)
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(
    client_saved_submission_run_row(snapshot).unwrap().revision,
    9007199254740994L,
  )
  assert_true(
    read_client_scanned_submission_with_task_original(
      scanned,
      (table, key) => {
        if table == "client_runs" {
          Err("original-run-read-failure")
        } else {
          inventory_read(rows, table, key)
        }
      },
      _ => Err("must-not-run"),
      "custody",
      original,
    )
    is Err("original-run-read-failure"),
  )
}

///|
test "scanned row key revision and complete bytes cannot be substituted" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  let scanned = rows[3].1
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  for
    pointed in [
      { ..scanned, key: "foreign-key", },
      { ..scanned, revision: scanned.revision + 1L, },
      { ..scanned, body: @utf8.encode(saved_submission_preparing), },
      { ..scanned, body: @utf8.encode(saved_submission_ready + "\n"), },
    ] {
    assert_true(
      read_client_scanned_submission_with_task_original(
        scanned,
        (table, key) => {
          if table == "client_submitted_intents" {
            Ok(Some(pointed))
          } else {
            inventory_read(rows, table, key)
          }
        },
        _ => Ok(saved_snapshot_run()),
        "custody",
        original,
      )
      is Err("custody"),
    )
  }
  let phases = Ref(0)
  let changed = { ..scanned, revision: scanned.revision + 1L, }
  assert_true(
    read_client_scanned_submission_with_task_original(
      scanned,
      (table, key) => {
        if table == "client_submitted_intents" {
          Ok(Some(changed))
        } else {
          inventory_read(rows, table, key)
        }
      },
      _ => Err("original-validator-failure"),
      "custody",
      original,
      before_construction=Some(_ => {
        phases.val += 1
        Ok(())
      }),
    )
    is Err("original-validator-failure"),
  )
  assert_eq(phases.val, 4) // Miss keeps both original decodes before that failure.
}

///|
test "scanned malformed or unfunded decode refuses before physical IO" {
  let scanned = saved_snapshot_rows(saved_submission_ready)[3].1
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  let reads = Ref(0)
  let read = (_, _) => {
    reads.val += 1
    Err("must-not-read")
  }
  assert_true(
    read_client_scanned_submission_with_task_original(
      { ..scanned, body: b"{", },
      read,
      _ => Err("must-not-validate"),
      "custody",
      original,
    )
    is Err("custody"),
  )
  assert_true(
    read_client_scanned_submission_with_task_original(
      scanned,
      read,
      _ => Err("must-not-validate"),
      "custody",
      original,
      before_construction=Some(_ => Err(CustodyLost)),
    )
    is Err("custody"),
  )
  assert_eq(reads.val, 0)
  assert_true(
    read_client_scanned_submission_with_task_original(
      scanned,
      (_, _) => Err("original-point-failure"),
      _ => Err("must-not-validate"),
      "custody",
      original,
    )
    is Err("original-point-failure"),
  )
  assert_true(
    read_client_scanned_submission_with_task_original(
      scanned,
      (_, _) => Ok(None),
      _ => Err("must-not-validate"),
      "custody",
      original,
    )
    is Err("custody"),
  )
}
