///|
test "Run observation row extension preserves absent-field legacy bytes" {
  let record = journal_encoding_original()
  let old = client_run_journal_row_body(record).unwrap()
  assert_eq(
    client_run_journal_row_body(record, run_observation_originals=None).unwrap(),
    old,
  )
  let decoded = decode_client_run_journal_row_with_observation_originals(old).unwrap()
  assert_eq(decoded.1, None)
  assert_eq(decoded.2, None)
  assert_eq(client_run_journal_row_body(decoded.0).unwrap(), old)
  assert_true(decode_client_run_journal_row(old) is Ok(_))
}

///|
test "Run observation row projection keeps raw originals separate from permission and old readers" {
  let record = journal_encoding_original()
  let raw = "{\"authorization\":\"original-auth\",\"prepared\":\"original-prepared\"}"
  let body = client_run_journal_row_body(
    record,
    local_run_policy_originals=Some("original-finite-policy"),
    run_observation_originals=Some(raw),
  ).unwrap()
  let decoded = decode_client_run_journal_row_with_observation_originals(body).unwrap()
  assert_eq(decoded.1, Some("original-finite-policy"))
  assert_eq(decoded.2, Some(raw))
  assert_false(decoded.0.dispatch_reserved)
  assert_false(decoded.0.physical_start_claimed)
  assert_eq(
    client_run_journal_row_body(
      decoded.0,
      local_run_policy_originals=decoded.1,
      run_observation_originals=decoded.2,
    ).unwrap(),
    body,
  )
  assert_true(decode_client_run_journal_row(body) is Err(CustodyLost))
  assert_true(
    decode_client_run_journal_row_with_local_policy(body) is Err(CustodyLost),
  )
}

///|
test "Run observation row extension refuses unknown duplicate null and over-capacity data" {
  let body = client_run_journal_row_body(
    journal_encoding_original(),
    run_observation_originals=Some("original-observation"),
  ).unwrap()
  let wire = @utf8.decode(body)
  for
    candidate in [
      wire.replace(
        old="\"run_observation_originals\":\"original-observation\"",
        new="\"run_observation_originals\":null",
      ),
      wire.replace(
        old="\"run_observation_originals\":\"original-observation\"",
        new="\"run_observation_originals\":\"original-observation\",\"run_observation_originals\":\"other\"",
      ),
      wire.replace(
        old="\"run_observation_originals\":",
        new="\"unknown_originals\":",
      ),
    ] {
    assert_true(
      decode_client_run_journal_row_with_observation_originals(
        @utf8.encode(candidate),
      )
      is Err(CustodyLost),
    )
  }
  assert_eq(
    client_run_journal_row_body(
      journal_encoding_original(),
      run_observation_originals=Some("x".repeat(131073)),
    ),
    Err(CapacityExceeded),
  )
}
