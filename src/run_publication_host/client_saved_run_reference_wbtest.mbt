///|
fn saved_reference_rows() -> Array[(String, ClientJournalPhysicalRow)] {
  saved_snapshot_rows(
    saved_submission_ready.replace(old="9007199254740993", new="0"),
  )
}

///|
fn saved_reference_select(
  rows : Array[(String, ClientJournalPhysicalRow)],
  namespace_scope? : String = "scope",
  authority? : String = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  definition? : String = "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
) -> Result[ClientSavedSubmissionSnapshot?, String] {
  inspect_client_saved_run_reference(
    namespace_scope,
    authority,
    definition,
    1024,
    (table, cursor) => inventory_scan(rows, table, cursor),
    (table, key) => inventory_read(rows, table, key),
    _ => Ok(saved_snapshot_run()),
    () => Ok(()),
    "custody",
  )
}

///|
test "saved public Run selection retains its actual original admission and bytes" {
  let snapshot = saved_reference_select(saved_reference_rows())
    .unwrap()
    .unwrap()
  assert_eq(
    client_saved_submission_admission_wire(snapshot).unwrap(),
    saved_admission_public_wire,
  )
  assert_eq(client_saved_submission_revision(snapshot), 6L)
  assert_eq(
    client_saved_submission_run_row(snapshot).unwrap().body,
    b"actual-original-run",
  )
  assert_eq(
    client_submission_reference_record_wire(
      client_saved_submission_record(snapshot).reference,
    ),
    client_submission_reference_record_wire(saved_snapshot_reference()),
  )
}

///|
test "Run reference equality never substitutes a namespace scope or definition" {
  let rows = saved_reference_rows()
  for
    selected in [
      saved_reference_select(rows, namespace_scope="foreign"),
      saved_reference_select(
        rows,
        authority="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      saved_reference_select(
        rows,
        definition="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
    ] {
    assert_true(selected is Ok(None))
  }
  assert_true(
    saved_reference_select(saved_snapshot_rows(saved_submission_preparing))
    is Ok(None),
  )
}

///|
test "matching Run cannot hide a corrupt later original Submission" {
  let rows = saved_reference_rows()
  rows[1] = ("client_submitted_intent_custody", inventory_row("issued", b"2"))
  rows.push(("client_submitted_intents", inventory_row("zz-hidden", b"broken")))
  assert_true(saved_reference_select(rows) is Err("custody"))
}

///|
test "Run reference selection propagates original read and cancellation failures" {
  let rows = saved_reference_rows()
  for fail_read in [false, true] {
    let result = inspect_client_saved_run_reference(
      "scope",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => {
        if fail_read {
          Err("original-read")
        } else {
          inventory_read(rows, table, key)
        }
      },
      _ => Ok(saved_snapshot_run()),
      () => Err("cancellation"),
      "custody",
    )
    assert_true(result is Err(_))
  }
}
