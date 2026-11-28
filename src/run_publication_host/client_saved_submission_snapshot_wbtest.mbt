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
    cancellation_head: None,
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

///|
test "single-pass nominal saved reader keeps construction fences and fresh material" {
  let wire = "original task materials"
  let cid = "sha256:999ffd0893e091d256f0094891b3a4e04c5a0ee224d42139336bf403a970c170"
  let original = { ..saved_snapshot_run(), task_materials_cid: Some(cid), }
  let key = client_request_scope_cid(original.request)
  let rows = saved_snapshot_rows(saved_submission_ready)
  rows.push(
    ("client_task_run_materials", inventory_row(key + ":0", @utf8.encode(wire))),
  )
  let stages = Ref(0)
  let chunk_reads = Ref(0)
  let changed = Ref(false)
  let read = (table, name) => {
    if table == "client_task_run_materials" {
      chunk_reads.val += 1
      if changed.val && name == key + ":0" {
        return Ok(None)
      }
    }
    inventory_read(rows, table, name)
  }
  let snapshot = read_client_saved_submission(
      saved_snapshot_reference(),
      read,
      _ => Ok(original),
      "custody",
      before_construction=Some(_ => {
        stages.val += 1
        Ok(())
      }),
    )
    .unwrap()
    .unwrap()
  assert_eq(
    client_saved_submission_task_materials_original(snapshot),
    Some(wire),
  )
  // Existing observed decoding admits Parse and Canonical once each.
  assert_eq(stages.val, 2)
  assert_eq(chunk_reads.val, 4)
  changed.val = true
  assert_true(
    read_client_saved_submission(
      saved_snapshot_reference(),
      read,
      _ => Ok(original),
      "custody",
      before_construction=Some(_ => {
        stages.val += 1
        Ok(())
      }),
    )
    is Err("custody"),
  )
  assert_eq(stages.val, 4)
  assert_eq(chunk_reads.val, 8)
  let before = chunk_reads.val
  assert_true(
    read_client_saved_submission(
      saved_snapshot_reference(),
      read,
      _ => Ok(original),
      "custody",
      before_construction=Some(_ => Err(CustodyLost)),
    )
    is Err("custody"),
  )
  assert_eq(chunk_reads.val, before)
}

///|
test "retained material saved reader retains original construction and physical fences" {
  let wire = "original task materials"
  let run = saved_snapshot_run()
  let key = client_request_scope_cid(run.request)
  let original = capture_client_task_materials_original(
    (),
    key,
    wire,
    () => Ok("policy"),
    _ => "encoding",
  ).unwrap()
  let pointed = {
    ..run,
    task_materials_cid: Some(client_task_materials_original_cid(original)),
  }
  let rows = saved_snapshot_rows(saved_submission_ready)
  rows.push(
    ("client_task_run_materials", inventory_row(key + ":0", @utf8.encode(wire))),
  )
  let chunks = Ref(0)
  let constructors = Ref(0)
  let validators = Ref(0)
  let changed = Ref(false)
  let read = (table, name) => {
    if table == "client_task_run_materials" {
      chunks.val += 1
      if changed.val && name == key + ":0" {
        return Ok(None)
      }
    }
    inventory_read(rows, table, name)
  }
  let validate = _ => {
    validators.val += 1
    Ok(pointed)
  }
  let snapshot = read_client_saved_submission_with_task_original(
      saved_snapshot_reference(),
      read,
      validate,
      "custody",
      Some(original),
      before_construction=Some(_ => {
        constructors.val += 1
        Ok(())
      }),
    )
    .unwrap()
    .unwrap()
  assert_eq(
    client_saved_submission_task_materials_original(snapshot),
    Some(wire),
  )
  assert_eq(chunks.val, 4)
  assert_eq(constructors.val, 2)
  assert_eq(validators.val, 1)
  changed.val = true
  assert_true(
    read_client_saved_submission_with_task_original(
      saved_snapshot_reference(),
      read,
      validate,
      "custody",
      Some(original),
      before_construction=Some(_ => {
        constructors.val += 1
        Ok(())
      }),
    )
    is Err("custody"),
  )
  assert_eq(chunks.val, 8)
  assert_eq(constructors.val, 4)
  assert_eq(validators.val, 2)
  assert_true(
    read_client_saved_submission_with_task_original(
      saved_snapshot_reference(),
      read,
      validate,
      "custody",
      Some(original),
      before_construction=Some(_ => Err(CustodyLost)),
    )
    is Err("custody"),
  )
  assert_eq(chunks.val, 8)
  assert_eq(validators.val, 2)
}

///|
test "target cancellation reads only a checked Run's accepted head" {
  let ready = saved_snapshot_inspect(
      saved_snapshot_rows(saved_submission_ready),
    )
    .unwrap()
    .unwrap()
  let preparing_rows = saved_snapshot_rows(saved_submission_preparing)
  let preparing = read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => inventory_read(preparing_rows, table, key),
      _ => Err("unexpected Run"),
      "custody",
    )
    .unwrap()
    .unwrap()
  let read = (_, _) => Err("unexpected cancellation read")
  assert_true(
    confirm_client_saved_submission_cancellation(ready, read, "custody")
    is Ok(true),
  )
  assert_true(
    confirm_client_saved_submission_cancellation(preparing, read, "custody")
    is Ok(false),
  )
}
