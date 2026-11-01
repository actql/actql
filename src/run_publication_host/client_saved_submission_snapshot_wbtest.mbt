///|
fn saved_snapshot_reference() -> ClientSubmissionReferenceRecord {
  decode_client_submitted_journal_row(@utf8.encode(saved_submission_ready)).unwrap().reference
}

///|
fn saved_snapshot_run() -> ClientRunJournalInspection {
  let admission = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap().run_admission.unwrap()
  {
    request: admission.0,
    definition: saved_submission_definition(),
    checkpoint: None,
    task_materials_cid: None,
  }
}

///|
fn saved_snapshot_rows(
  body : String,
) -> Array[(String, ClientJournalPhysicalRow)] {
  [
    ("client_run_custody", inventory_row("issued", b"1")),
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    (
      "client_runs",
      inventory_row(
        "sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918",
        b"actual-original-run",
        revision=9007199254740994L,
      ),
    ),
    (
      "client_submitted_intents",
      inventory_row(
        "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
        @utf8.encode(body),
        revision=6L,
      ),
    ),
  ]
}

///|
fn saved_snapshot_inspect(
  rows : Array[(String, ClientJournalPhysicalRow)],
) -> Result[ClientSavedSubmissionSnapshot?, String] {
  inspect_client_saved_submission(
    saved_snapshot_reference(),
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    _ => Ok(saved_snapshot_run()),
    () => Ok(()),
    "custody",
  )
}

///|
test "original preparing and missing saved observations do not claim Run admission" {
  let rows = saved_snapshot_rows(saved_submission_preparing)
  let runs : Array[String] = []
  let snapshot = read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => {
        if table == "client_runs" {
          runs.push(key)
        }
        inventory_read(rows, table, key)
      },
      _ => Err("must-not-validate-Run"),
      "custody",
    )
    .unwrap()
    .unwrap()
  assert_true(client_saved_submission_record(snapshot).run_admission is None)
  assert_true(client_saved_submission_run_row(snapshot) is None)
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(runs, [])
  assert_true(
    read_client_saved_submission(
      saved_snapshot_reference(),
      (_, _) => Ok(None),
      _ => Err("must-not-validate-Run"),
      "custody",
    )
    is Ok(None),
  )
}

///|
test "saved snapshot preserves actual rows and original admission rather than later revision" {
  let snapshot = saved_snapshot_inspect(
      saved_snapshot_rows(saved_submission_ready),
    )
    .unwrap()
    .unwrap()
  let record = client_saved_submission_record(snapshot)
  assert_eq(record.run_admission.unwrap().2, 9007199254740993L)
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  let run = client_saved_submission_run_row(snapshot).unwrap()
  assert_eq(run.body, b"actual-original-run")
  assert_eq(run.revision, 9007199254740994L)
  assert_eq(
    client_saved_submission_row(snapshot).body,
    @utf8.encode(saved_submission_ready),
  )
  assert_eq(
    client_submitted_intent_wire(record.intent),
    saved_submission_intent,
  )
}

///|
test "changed original Reference refuses before any dependent Run lookup" {
  let record = saved_snapshot_reference()
  let changed = admit_client_submission_reference_record(
    client_submission_reference_record_wire(record).replace(
      old="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      new="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
  ).unwrap()
  // The shape fixture intentionally does not assert HMAC authentication.
  let rows = saved_snapshot_rows(saved_submission_ready)
  let runs : Array[String] = []
  assert_true(
    read_client_saved_submission(
      changed,
      (table, key) => {
        if table == "client_runs" {
          runs.push(key)
        }
        inventory_read(rows, table, key)
      },
      _ => Ok(saved_snapshot_run()),
      "custody",
    )
    is Err("custody"),
  )
  assert_eq(runs, [])
}

///|
test "saved ready record requires actual retained Run original identity and sufficient revision" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  rows[2] = (
    "client_runs",
    inventory_row(
      "sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918",
      b"actual-original-run",
      revision=9007199254740992L,
    ),
  )
  assert_true(saved_snapshot_inspect(rows) is Err("custody"))
  let missing = saved_snapshot_rows(saved_submission_ready)
  assert_true(
    read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => {
        if table == "client_runs" {
          Ok(None)
        } else {
          inventory_read(missing, table, key)
        }
      },
      _ => Ok(saved_snapshot_run()),
      "custody",
    )
    is Err("custody"),
  )
  assert_true(
    read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => inventory_read(missing, table, key),
      _ => {
        Ok({
          ..saved_snapshot_run(),
          request: journal_encoding_original().request,
        })
      },
      "custody",
    )
    is Err("custody"),
  )
  let changed_definition = saved_snapshot_rows(
    saved_submission_ready.replace(
      old="sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      new="sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    ),
  )
  assert_true(saved_snapshot_inspect(changed_definition) is Err("custody"))
}

///|
test "saved read propagates query and nested-original failures instead of missing history" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  for failed in ["client_submitted_intents", "client_runs"] {
    assert_true(
      read_client_saved_submission(
        saved_snapshot_reference(),
        (table, key) => {
          if table == failed {
            Err("query")
          } else {
            inventory_read(rows, table, key)
          }
        },
        _ => Ok(saved_snapshot_run()),
        "custody",
      )
      is Err("query"),
    )
  }
  assert_true(
    read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("nested-originals"),
      "custody",
    )
    is Err("nested-originals"),
  )
}

///|
test "whole saved observation refuses orphan inventory before reading target Submission" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  rows.push(
    ("client_effect_response_bytes", inventory_row("orphan", b"not-owned")),
  )
  let targets : Array[String] = []
  assert_true(
    inspect_client_saved_submission(
      saved_snapshot_reference(),
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => {
        if table == "client_submitted_intents" {
          targets.push(key)
        }
        inventory_read(rows, table, key)
      },
      _ => Ok(saved_snapshot_run()),
      () => Ok(()),
      "custody",
    )
    is Err("custody"),
  )
  assert_eq(targets, [])
}

///|
test "whole saved observation cannot omit unknown Submitted row behind fixed count" {
  let rows = saved_snapshot_rows(saved_submission_ready)
  rows.push(
    (
      "client_submitted_intents",
      inventory_row("unknown-target", @utf8.encode(saved_submission_preparing)),
    ),
  )
  assert_true(saved_snapshot_inspect(rows) is Err("custody"))
  rows[1] = ("client_submitted_intent_custody", inventory_row("issued", b"2"))
  // Updating a count alone does not validate a forged row/key relationship.
  assert_true(saved_snapshot_inspect(rows) is Err("custody"))
}

///|
test "whole saved observation preserves unresolved complete empty history and cancellation failure" {
  let empty = [
    ("client_run_custody", inventory_row("issued", b"0")),
    ("client_submitted_intent_custody", inventory_row("issued", b"0")),
  ]
  assert_true(saved_snapshot_inspect(empty) is Ok(None))
  let rows = saved_snapshot_rows(saved_submission_ready)
  assert_true(
    inspect_client_saved_submission(
      saved_snapshot_reference(),
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      _ => Ok(saved_snapshot_run()),
      () => Err("cancel-custody"),
      "custody",
    )
    is Err("cancel-custody"),
  )
}
