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
    @publication.publication_contract_json(state.original_manifest()),
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
