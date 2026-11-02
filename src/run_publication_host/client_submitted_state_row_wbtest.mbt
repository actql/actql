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

///|
test "fresh observation counter is explicit and legacy absence remains absent" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  assert_true(record.run_state_observation is None)
  let reference = client_submission_reference_record_wire(record.reference)
  let fresh = client_submitted_intent_journal_row_body(
    reference,
    record.intent,
    run_admission=record.run_admission,
    run_state_observation=Some((0L, None)),
  ).unwrap()
  // Independently specified additional fields and canonical placement.
  let expected = saved_submission_ready.replace(
    old="\"version\":\"actql-native-client-submitted-intent-row/0.1\"",
    new="\"run_state_key\":null,\"run_state_revision\":0,\"version\":\"actql-native-client-submitted-intent-row/0.1\"",
  )
  assert_eq(fresh, @utf8.encode(expected))
  let read = decode_client_submitted_journal_row(fresh).unwrap()
  assert_eq(read.run_state_observation, Some((0L, None)))
  assert_true(read.run_state_original is None)
  assert_eq(read.run_admission.unwrap().2, 9007199254740993L)
}

///|
test "saved observation counter and key roundtrip without changing admitted revision" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  for revision in [0L, 19L, 9007199254740991L] {
    let body = client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(record.reference),
      record.intent,
      run_admission=record.run_admission,
      run_state_original=Some("original metadata"),
      run_state_observation=Some((revision, Some("original observation key"))),
    ).unwrap()
    let read = decode_client_submitted_journal_row(body).unwrap()
    assert_eq(
      read.run_state_observation,
      Some((revision, Some("original observation key"))),
    )
    assert_eq(read.run_admission.unwrap().2, 9007199254740993L)
    assert_eq(
      client_submitted_intent_journal_row_body(
        client_submission_reference_record_wire(read.reference),
        read.intent,
        run_admission=read.run_admission,
        run_state_original=read.run_state_original,
        run_state_observation=read.run_state_observation,
      ).unwrap(),
      body,
    )
  }
}

///|
test "observation row refuses partial unsafe noncanonical and duplicate counter metadata" {
  for
    fields in [
      "\"run_state_key\":null,", "\"run_state_revision\":0,", "\"run_state_key\":null,\"run_state_revision\":1,",
      "\"run_state_key\":null,\"run_state_revision\":-1,", "\"run_state_key\":null,\"run_state_revision\":9007199254740992,",
      "\"run_state_key\":null,\"run_state_revision\":\"0\",", "\"run_state_key\":null,\"run_state_revision\":0.0,",
      "\"run_state_key\":null,\"run_state_revision\":0,\"run_state_revision\":0,",
      "\"run_state_key\":\"\",\"run_state_original\":\"saved\",\"run_state_revision\":0,",
      "\"run_state_key\":\"key\",\"run_state_revision\":0,", "\"run_state_key\":false,\"run_state_revision\":0,",
    ] {
    let wire = saved_submission_ready.replace(
      old="\"version\":",
      new=fields + "\"version\":",
    )
    assert_true(
      decode_client_submitted_journal_row(@utf8.encode(wire))
      is Err(CustodyLost),
    )
  }
  let preparing = saved_submission_preparing.replace(
    old="\"version\":",
    new="\"run_state_key\":null,\"run_state_revision\":0,\"version\":",
  )
  assert_true(
    decode_client_submitted_journal_row(@utf8.encode(preparing))
    is Err(CustodyLost),
  )
}

///|
test "observation metadata consumes original row capacity without enlarging it" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  assert_true(
    client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(record.reference),
      record.intent,
      run_admission=record.run_admission,
      run_state_original=Some("s".repeat(131072)),
      run_state_observation=Some((0L, Some("k".repeat(131072)))),
    )
    is Err(CapacityExceeded),
  )
}

///|
test "accepted preparation failure decodes without Run and preserves original identity" {
  // Independent extension of the fixed original row. No product encoder
  // supplies the expected phase or problem, and no physical ACK is inferred.
  let body = saved_submission_preparing.replace(
    old="\"phase\":\"preparing\",\"reference\":",
    new="\"phase\":\"preparation_failed\",\"preparation_problem_classification\":\"invalid_input\",\"preparation_problem_code\":\"ClientProgramInvalidInput\",\"reference\":",
  )
  assert_true(decode_client_submitted_journal_row(@utf8.encode(body)) is Ok(_))
}
