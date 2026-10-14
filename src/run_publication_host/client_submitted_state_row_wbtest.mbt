///|
test "saved Submission optional state preserves old bytes and immutable admission revision" {
  let original = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  assert_true(original.run_state_original is None)
  let reference = client_submission_reference_record_wire(original.reference)
  let old = client_submitted_intent_journal_row_body(
    reference,
    original.intent,
    run_admission=original.run_admission,
  ).unwrap()
  assert_eq(old, @utf8.encode(saved_submission_ready))
  let body = client_submitted_intent_journal_row_body(
    reference,
    original.intent,
    run_admission=original.run_admission,
    run_state_original=Some("original metadata"),
  ).unwrap()
  let read = decode_client_submitted_journal_row(body).unwrap()
  assert_eq(read.run_state_original, Some("original metadata"))
  assert_eq(read.run_admission.unwrap().2, 9007199254740993L)
  assert_eq(
    client_submitted_intent_cid(read.intent),
    saved_submission_intent_cid,
  )
  assert_eq(
    client_submitted_intent_journal_row_body(
      reference,
      read.intent,
      run_admission=read.run_admission,
      run_state_original=read.run_state_original,
    ).unwrap(),
    body,
  )
}

///|
test "saved Submission state rejects preparing NULL duplicate noncanonical and original bounds" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let reference = client_submission_reference_record_wire(record.reference)
  assert_true(
    client_submitted_intent_journal_row_body(
      reference,
      record.intent,
      run_state_original=Some("metadata"),
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    client_submitted_intent_journal_row_body(
      reference,
      record.intent,
      run_admission=record.run_admission,
      run_state_original=Some("x".repeat(131073)),
    )
    is Err(CapacityExceeded),
  )
  for
    wire in [
      saved_submission_ready.replace(
        old="\"version\":",
        new="\"run_state_original\":null,\"version\":",
      ),
      saved_submission_ready.replace(
        old="\"version\":",
        new="\"run_state_original\":\"a\",\"run_state_original\":\"b\",\"version\":",
      ),
      saved_submission_preparing.replace(
        old="\"version\":",
        new="\"run_state_original\":\"a\",\"version\":",
      ),
      " " + saved_submission_ready,
    ] {
    assert_true(
      decode_client_submitted_journal_row(@utf8.encode(wire))
      is Err(CustodyLost),
    )
  }
}
