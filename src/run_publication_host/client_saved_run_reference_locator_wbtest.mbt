///|
fn saved_locator_rows() -> (Array[(String, ClientJournalPhysicalRow)], String) {
  let run = saved_snapshot_run()
  let (key, body) = client_saved_run_reference_locator(
    saved_snapshot_reference(),
    run.request,
    run.definition,
  ).unwrap()
  let rows = saved_reference_rows()
  rows.push(("client_run_reference_index", inventory_row(key, body)))
  (rows, key)
}

///|
fn saved_locator_read(
  rows : Array[(String, ClientJournalPhysicalRow)],
  calls : Array[String],
) -> Result[ClientSavedSubmissionSnapshot, String] {
  let run = saved_snapshot_run()
  read_client_saved_run_reference(
    @publication.run_definition_namespace(run.definition).unwrap(),
    client_request_authority_scope_cid(run.request),
    @publication.publication_contract_identity(run.definition),
    (table, key) => {
      calls.push("read:" + table + ":" + key)
      inventory_read(rows, table, key)
    },
    _ => {
      calls.push("validate-selected-run")
      Ok(run)
    },
    "custody",
  )
}

///|
test "saved Run reference locator reads one selected original without unrelated inventory" {
  let (rows, _) = saved_locator_rows()
  rows.push(
    (
      "client_submitted_intents",
      inventory_row("unrelated", b"invalid unrelated row"),
    ),
  )
  let calls : Array[String] = []
  let snapshot = saved_locator_read(rows, calls).unwrap()
  assert_eq(
    client_submission_reference_record_wire(snapshot.record.reference),
    client_submission_reference_record_wire(saved_snapshot_reference()),
  )
  assert_eq(calls.filter(value => value.has_prefix("read:")).length(), 3)
  assert_eq(calls.filter(value => value == "validate-selected-run").length(), 1)
  assert_false(calls.any(value => value.has_suffix(":unrelated")))
}

///|
test "saved Run locator missing coverage and corrupt selected originals never imply absence" {
  let (rows, _) = saved_locator_rows()
  assert_true(saved_locator_read(saved_reference_rows(), []) is Err("custody"))
  rows[rows.length() - 1] = (
    "client_run_reference_index",
    inventory_row(rows[rows.length() - 1].1.key, b"ambiguous"),
  )
  assert_true(saved_locator_read(rows, []) is Err("custody"))
  let (rows, _) = saved_locator_rows()
  rows[3] = (
    "client_submitted_intents",
    inventory_row(rows[3].1.key, b"changed original"),
  )
  assert_true(saved_locator_read(rows, []) is Err("custody"))
}

///|
test "saved Run locator requires original namespace scope definition and nested validator" {
  let (rows, key) = saved_locator_rows()
  let run = saved_snapshot_run()
  let read = (table, wanted) => {
    // Even a physical port returning a valid locator under a foreign selector
    // cannot substitute the original scope/namespace/definition.
    if table == "client_run_reference_index" {
      let row = inventory_read(rows, table, key).unwrap().unwrap()
      Ok(Some({ ..row, key: wanted, }))
    } else {
      inventory_read(rows, table, wanted)
    }
  }
  assert_true(
    read_client_saved_run_reference(
      "foreign",
      client_request_authority_scope_cid(run.request),
      @publication.publication_contract_identity(run.definition),
      read,
      _ => Ok(run),
      "custody",
    )
    is Err("custody"),
  )
  assert_true(
    read_client_saved_run_reference(
      @publication.run_definition_namespace(run.definition).unwrap(),
      client_request_authority_scope_cid(run.request),
      @publication.publication_contract_identity(run.definition),
      read,
      _ => Err("nested-original"),
      "custody",
    )
    is Err("nested-original"),
  )
  assert_true(
    read_client_saved_run_reference(
      @publication.run_definition_namespace(run.definition).unwrap(),
      client_request_authority_scope_cid(run.request),
      @publication.publication_contract_identity(run.definition),
      (_, _) => Err("query"),
      _ => Ok(run),
      "custody",
    )
    is Err("query"),
  )
}
