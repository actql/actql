///|
// Source-only retained-original decision. Observer callbacks here record phase
// forwarding, not a physical Read, resource reservation or permission.
test "retained large append uses the same full observed decoder without insertion" {
  let original = append_original_record()
  let wire = "{\"input\":{\"text\":\"" +
    "x".repeat(300000) +
    "\"},\"kind\":\"aql\",\"parameters\":null}"
  let intent = prepare_client_submitted_intent(wire, 400000, 64, 8).unwrap()
  let body = client_submitted_intent_journal_row_body(
    client_submission_reference_record_wire(original.reference),
    intent,
    before_construction=Some((_, _, _) => Ok(())),
  ).unwrap()
  let rows = [
    ("client_submitted_intent_custody", inventory_row("issued", b"1")),
    (
      "client_submitted_intents",
      inventory_row(append_request_id, body, revision=9L),
    ),
  ]
  let mut decoded = 0
  let mut constructed = 0
  let decide = observer => {
    prepare_client_submitted_journal_append(
      original.reference,
      intent,
      @request_scope.Expired,
      1024,
      (table, cursor) => inventory_scan(rows, table, cursor),
      (table, key) => inventory_read(rows, table, key),
      _ => Err("unexpected-inventory"),
      _ => Err("unexpected-Run"),
      "custody",
      before_decode_construction=observer,
      before_construction=Some((_, _, _) => {
        constructed += 1
        Err(CapacityExceeded)
      }),
    )
  }
  assert_true(decide(None) is Err(Observation("custody")))
  guard decide(
      Some(_ => {
        decoded += 1
        Ok(())
      }),
    )
    is Ok(Retained(snapshot)) else {
    fail("large retained original lost")
  }
  assert_eq(client_saved_submission_revision(snapshot), 9L)
  assert_eq(client_saved_submission_record(snapshot).intent, intent)
  assert_eq(decoded, 2)
  assert_eq(constructed, 0)
  assert_true(
    decide(Some(_ => Err(CustodyLost))) is Err(Observation("custody")),
  )
  assert_eq(constructed, 0)
}
