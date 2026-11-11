///|
test "observed cold row retains exact original identity and same-parse geometry" {
  let original = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_preparing),
  ).unwrap()
  let wire = "{\"input\":{\"text\":\"" +
    "é\\r\\n".repeat(45000) +
    "\"},\"kind\":\"aql\",\"parameters\":null}"
  let intent = prepare_client_submitted_intent(wire, 1000000, 64, 8).unwrap()
  let body = client_submitted_intent_journal_row_body(
    client_submission_reference_record_wire(original.reference),
    intent,
    before_construction=Some((_, _, _) => Ok(())),
  ).unwrap()
  let observed : Array[(Int, Int, Int)] = []
  let restored = decode_client_submitted_journal_row(
    body,
    before_construction=Some(stage => {
      match stage {
        SubmittedJournalParse(bytes) => observed.push((bytes, 0, 0))
        SubmittedJournalCanonical(bytes, _text_units, nodes, depth) =>
          observed.push((bytes, nodes, depth))
      }
      Ok(())
    }),
  ).unwrap()
  assert_eq(restored.intent, intent)
  assert_true(body.length() > 262144)
  assert_true(decode_client_submitted_journal_row(body) is Err(CustodyLost))
  assert_eq(observed.length(), 2)
  assert_eq(observed[0], (body.length(), 0, 0))
  assert_true(observed[1].1 > 0 && observed[1].1 < 64)
  assert_true(observed[1].2 > 0 && observed[1].2 < 8)
  let snapshot = read_client_saved_submission(
      original.reference,
      (table, key) => {
        if table == "client_submitted_intents" {
          Ok(Some({ key, revision: 7L, body, }))
        } else {
          Ok(None)
        }
      },
      _ => Err(ClientJournalDecodingIssue::CustodyLost),
      ClientJournalDecodingIssue::CustodyLost,
      before_construction=Some(_ => Ok(())),
    )
    .unwrap()
    .unwrap()
  assert_eq(client_saved_submission_revision(snapshot), 7L)
  assert_eq(client_saved_submission_record(snapshot).intent, intent)
}

///|
test "observed cold row resource refusal cannot replace canonical admission" {
  let bytes = @utf8.encode(saved_submission_preparing)
  let mut calls = 0
  assert_true(
    decode_client_submitted_journal_row(
      bytes,
      before_construction=Some(_ => {
        calls += 1
        Err(CustodyLost)
      }),
    )
    is Err(CustodyLost),
  )
  assert_eq(calls, 1)
  let mut canonical_calls = 0
  assert_true(
    decode_client_submitted_journal_row(
      bytes,
      before_construction=Some(stage => {
        match stage {
          SubmittedJournalParse(_) => Ok(())
          SubmittedJournalCanonical(_, _, _, _) => {
            canonical_calls += 1
            Err(CustodyLost)
          }
        }
      }),
    )
    is Err(CustodyLost),
  )
  assert_eq(canonical_calls, 1)
  for
    invalid in [
      b" " + bytes,
      bytes + b" ",
      b"{}",
      b"{\"intent\":\"{}\",\"intent\":\"{}\"}",
    ] {
    assert_true(
      decode_client_submitted_journal_row(
        invalid,
        before_construction=Some(_ => Ok(())),
      )
      is Err(CustodyLost),
    )
  }
}
