///|
fn saved_original_row_fields(
  row : ClientJournalPhysicalRow,
) -> (String, Int64, Bytes) {
  (row.key, row.revision, row.body)
}

///|
test "same saved original reobserves both physical triples without rebuilding Manifest state" {
  let body = saved_state_snapshot_body(
    Some(client_saved_manifest_envelope),
    true,
  )
  let validations : Array[String] = []
  let original = saved_state_snapshot_read(body, validations).unwrap().unwrap()
  let rows = saved_snapshot_rows(body)
  let reads : Array[String] = []
  let actual = reobserve_client_saved_submission_original(original, (table, key) => {
      let result = inventory_read(rows, table, key)
      if result is Ok(_) {
        reads.push(table)
      }
      result
    })
    .unwrap()
    .unwrap()
  assert_eq(reads, ["client_submitted_intents", "client_runs"])
  assert_eq(validations, ["original Run"])
  assert_eq(
    saved_original_row_fields(client_saved_submission_row(actual)),
    saved_original_row_fields(client_saved_submission_row(original)),
  )
  assert_eq(
    saved_original_row_fields(client_saved_submission_run_row(actual).unwrap()),
    saved_original_row_fields(
      client_saved_submission_run_row(original).unwrap(),
    ),
  )
  assert_eq(
    client_saved_submission_record(actual).run_state_original,
    Some(client_saved_manifest_envelope),
  )
  let state = client_saved_submission_state_original(actual).unwrap()
  assert_eq(state.wire(), client_saved_manifest_envelope)
  assert_eq(state.state_wire(), client_saved_manifest_state)
  assert_eq(
    @publication.publication_contract_json(state.original_manifest().unwrap()),
    client_saved_manifest_manifest,
  )
}

///|
test "changed missing or foreign row triples supply no original proof and query errors remain errors" {
  let original = saved_state_snapshot_read(
      saved_state_snapshot_body(Some(client_saved_manifest_envelope), true),
      [],
    )
    .unwrap()
    .unwrap()
  let body = @utf8.decode(client_saved_submission_row(original).body) catch {
    _ => abort("fixture UTF-8")
  }
  let rows = saved_snapshot_rows(body)
  for table in ["client_submitted_intents", "client_runs"] {
    for change in [0, 1, 2] {
      let changed = rows.map(pair => {
        let (name, row) = pair
        (
          name,
          if name == table {
            match change {
              0 => { ..row, key: "foreign", }
              1 => { ..row, revision: row.revision + 1L, }
              _ => { ..row, body: b"changed", }
            }
          } else {
            row
          },
        )
      })
      assert_true(
        reobserve_client_saved_submission_original(original, (name, key) => {
          inventory_read(changed, name, key)
        })
        is Ok(None),
      )
    }
    assert_true(
      reobserve_client_saved_submission_original(original, (name, key) => {
        if name == table {
          Ok(None)
        } else {
          inventory_read(rows, name, key)
        }
      })
      is Ok(None),
    )
    assert_true(
      reobserve_client_saved_submission_original(original, (name, key) => {
        if name == table {
          Err("query")
        } else {
          inventory_read(rows, name, key)
        }
      })
      is Err("query"),
    )
  }
}

///|
test "preparing and historical originals do not create missing state or a new validator result" {
  let preparing = read_client_saved_submission(
      saved_snapshot_reference(),
      (table, key) => {
        inventory_read(
          saved_snapshot_rows(saved_submission_preparing),
          table,
          key,
        )
      },
      _ => Err("must-not-validate"),
      "custody",
    )
    .unwrap()
    .unwrap()
  assert_true(
    reobserve_client_saved_submission_original(preparing, (_, _) => {
      Err("must-not-read")
    })
    is Ok(None),
  )
  let body = saved_state_snapshot_body(
    Some(client_saved_manifest_envelope),
    false,
  )
  let historical = saved_state_snapshot_read(body, []).unwrap().unwrap()
  let actual = reobserve_client_saved_submission_original(historical, (
      table,
      key,
    ) => inventory_read(saved_snapshot_rows(body), table, key))
    .unwrap()
    .unwrap()
  assert_true(client_saved_submission_state_original(actual) is None)
  assert_true(
    client_saved_submission_record(actual).run_state_observation is None,
  )
  assert_eq(
    client_saved_submission_record(actual).run_state_original,
    Some(client_saved_manifest_envelope),
  )
}

///|
test "same saved material reobserves the original canonical chunks and propagates the last query refusal" {
  let run = saved_snapshot_run()
  let key = client_request_scope_cid(run.request)
  let prefix = "a".repeat(131071)
  let material = prefix + "é-z"
  let cid = "sha256:6051d05c9a70bfcb9c63e649775bc787d6dc01497266aa2ff9e35ac9a185f324"
  let rows = saved_snapshot_rows(saved_submission_ready)
  rows.push(
    (
      "client_task_run_materials",
      inventory_row(key + ":0", @utf8.encode(prefix)),
    ),
  )
  rows.push(
    (
      "client_task_run_materials",
      inventory_row(key + ":1", @utf8.encode("é-z")),
    ),
  )
  let original = read_client_saved_submission(
      saved_snapshot_reference(),
      (table, name) => inventory_read(rows, table, name),
      _ => Ok({ ..run, task_materials_cid: Some(cid), }),
      "custody",
    )
    .unwrap()
    .unwrap()
  assert_eq(
    client_saved_submission_task_materials_original(original),
    Some(material),
  )
  let reads = []
  let actual = reobserve_client_saved_submission_original(original, (
      table,
      name,
    ) => {
      if table == "client_task_run_materials" {
        reads.push(name)
      }
      inventory_read(rows, table, name)
    })
    .unwrap()
    .unwrap()
  assert_true(physical_equal(actual, original))
  assert_eq(reads, [key + ":0", key + ":1", key + ":2", key + ":3"])
  assert_true(
    reobserve_client_saved_submission_original(original, (table, name) => {
      if table == "client_task_run_materials" && name == key + ":1" {
        Ok(Some(inventory_row(name, @utf8.encode("è-z"))))
      } else {
        inventory_read(rows, table, name)
      }
    })
    is Ok(None),
  )
  assert_true(
    reobserve_client_saved_submission_original(original, (table, name) => {
      if table == "client_task_run_materials" && name == key + ":3" {
        Err("fourth physical query")
      } else {
        inventory_read(rows, table, name)
      }
    })
    is Err("fourth physical query"),
  )
}
