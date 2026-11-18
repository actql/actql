///|
fn append_task_material_fixture() -> (
  Array[(String, ClientJournalPhysicalRow)],
  ClientTaskMaterialsOriginal[Int],
  ClientRunJournalInspection,
) {
  let run = saved_snapshot_run()
  let key = client_request_scope_cid(run.request)
  let wire = "retained € 😀\n".repeat(2048)
  let original = capture_client_task_materials_original(
    19,
    key,
    wire,
    () => Ok("original policy"),
    _ => "encoding",
  ).unwrap()
  let rows = saved_snapshot_rows(saved_submission_ready)
  for (name, body) in client_task_materials_original_chunks(original) {
    rows.push(
      ("client_task_run_materials", inventory_row(name, @utf8.encode(body))),
    )
  }
  (rows, original, { ..run, task_materials_cid: Some(original.cid), })
}

///|
test "submitted append early Retained keeps the same material through the complete callee" {
  let (rows, original, run) = append_task_material_fixture()
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let reads : Array[String] = []
  let validators = Ref(0)
  let constructors = Ref(0)
  let actual = prepare_client_submitted_journal_append_with_task_original(
    record.reference,
    record.intent,
    @request_scope.Admissible,
    1024,
    (_, _) => Err("early retained must not scan"),
    (table, key) => {
      reads.push(table)
      inventory_read(rows, table, key)
    },
    _ => Err("early retained must not run append callback"),
    _ => {
      validators.val += 1
      Ok(run)
    },
    "custody",
    Some(original),
    before_decode_construction=Some(_ => {
      constructors.val += 1
      Ok(())
    }),
    before_construction=Some((_, _, _) => Err(CapacityExceeded)),
  ).unwrap()
  guard actual is Retained(snapshot) else {
    fail("original retained branch lost")
  }
  let wire = client_saved_submission_task_materials_original(snapshot).unwrap()
  assert_eq(wire, original.wire)
  // The Wasm String is the existing immutable original, not another equal
  // encoded/hash-checked reconstruction. The complete append callee runs.
  assert_true(physical_equal(wire, original.wire))
  assert_eq(reads, [
    "client_submitted_intent_custody", "client_submitted_intents", "client_runs",
    "client_task_run_materials", "client_task_run_materials", "client_task_run_materials",
    "client_task_run_materials",
  ])
  assert_eq(validators.val, 1)
  assert_eq(constructors.val, 2)
}

///|
test "submitted append material reuse preserves cold foreign changed and construction refusal" {
  let (rows, original, run) = append_task_material_fixture()
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let foreign = capture_client_task_materials_original(
    20,
    client_request_scope_cid(run.request),
    "different immutable material",
    () => Ok("foreign policy"),
    _ => "encoding",
  ).unwrap()
  let chunks = Ref(0)
  let changed = Ref(false)
  let refuse = Ref(false)
  let inspect = candidate => {
    prepare_client_submitted_journal_append_with_task_original(
      record.reference,
      record.intent,
      @request_scope.Admissible,
      1024,
      (_, _) => Err("unexpected scan"),
      (table, key) => {
        if table == "client_task_run_materials" {
          chunks.val += 1
          if changed.val && key.has_suffix(":0") {
            return Ok(Some(inventory_row(key, b"changed immutable material")))
          }
        }
        inventory_read(rows, table, key)
      },
      _ => Err("unexpected append callback"),
      _ => Ok(run),
      "custody",
      candidate,
      before_decode_construction=Some(_ => {
        if refuse.val {
          Err(CustodyLost)
        } else {
          Ok(())
        }
      }),
    )
  }
  for candidate in [None, Some(foreign)] {
    guard inspect(candidate) is Ok(Retained(snapshot)) else {
      fail("cold/foreign original must keep full valid reader")
    }
    assert_eq(
      client_saved_submission_task_materials_original(snapshot),
      Some(original.wire),
    )
  }
  assert_eq(chunks.val, 8)
  changed.val = true
  assert_true(inspect(Some(original)) is Err(Observation("custody")))
  assert_eq(chunks.val, 12)
  changed.val = false
  refuse.val = true
  assert_true(inspect(Some(original)) is Err(Observation("custody")))
  assert_eq(chunks.val, 12)
}
