///|
// Actual original SQLite/explicit Crypto components only. This qualifies the
// existing Epoch operation and HMAC, not a fabricated Host Read or a grant.
test "initial control HMAC reuses custody SQL only within the same Epoch operation" {
  let database = epoch_test_database("initial-control-operation-sql")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let (key, _, _) = read_epoch_custody(database).unwrap()
  let payload = b"original control HMAC DATA only"
  let tag = crypto.hmac_sha256(key, payload).unwrap()
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  assert_true(
    authority.verify_control_payload_in_operation(
      payload,
      tag,
      reads=Some(operations.reads),
    )
    is Err(ScopeMismatch),
  )
  assert_eq(calls.length(), 0)
  authority.begin_operation(false)
  assert_true(
    authority
    .verify_control_payload_in_operation(
      payload,
      tag,
      reads=Some(operations.reads),
    )
    .unwrap(),
  )
  assert_eq(calls.filter(call => call.has_prefix("scan:")).length(), 2)
  assert_eq(calls.filter(call => call.has_prefix("read:")).length(), 1)
  calls.clear()
  for _ in 0..<3 {
    assert_true(
      authority
      .verify_control_payload_in_operation(
        payload,
        tag,
        reads=Some(operations.reads),
      )
      .unwrap(),
    )
  }
  assert_false(
    calls.any(call => call.has_prefix("scan:") || call.has_prefix("read:")),
  )
  // No MAC result is cached: a different tag is checked by actual Crypto.
  assert_false(
    authority
    .verify_control_payload_in_operation(
      payload,
      Bytes::make(32, 0),
      reads=Some(operations.reads),
    )
    .unwrap(),
  )
  assert_eq(authority.authenticated_epochs.length(), 0)
  authority.end_operation()
  assert_true(authority.observed_custody is None)
  authority.begin_operation(false)
  calls.clear()
  assert_true(
    authority
    .verify_control_payload_in_operation(
      payload,
      tag,
      reads=Some(operations.reads),
    )
    .unwrap(),
  )
  assert_eq(calls.filter(call => call.has_prefix("read:")).length(), 1)
  authority.end_operation()
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "initial control HMAC resamples changed key after the existing boundary invalidation" {
  let database = epoch_test_database("initial-control-key-boundary")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let (key, _, _) = read_epoch_custody(database).unwrap()
  let payload = b"same original control payload"
  let tag = crypto.hmac_sha256(key, payload).unwrap()
  authority.begin_operation(false)
  assert_true(
    authority.verify_control_payload_in_operation(payload, tag).unwrap(),
  )
  let row = database.read("client_submission_epoch", "authority").unwrap()
  let changed = crypto.random_bytes(32).unwrap()
  database.begin_immediate().unwrap()
  database
  .compare_exchange(
    "client_submission_epoch",
    "authority",
    row.revision,
    epoch_custody_body(changed, 0.0).unwrap(),
  )
  .unwrap()
  |> ignore
  database.commit().unwrap()
  // The same hook is used for actual relevant mutations and before the
  // post-callback boundary samples. No pre-callback key survives this cut.
  authority.invalidate_custody()
  assert_true(authority.observed_custody is None)
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  authority.require_operation_current(Some(operations.reads)).unwrap()
  authority.custody(Some(operations.reads)).unwrap() |> ignore
  assert_eq(calls.filter(call => call.has_prefix("read:")).length(), 1)
  calls.clear()
  assert_false(
    authority
    .verify_control_payload_in_operation(
      payload,
      tag,
      reads=Some(operations.reads),
    )
    .unwrap(),
  )
  assert_true(
    authority
    .verify_control_payload_in_operation(
      payload,
      crypto.hmac_sha256(changed, payload).unwrap(),
      reads=Some(operations.reads),
    )
    .unwrap(),
  )
  assert_false(calls.any(call => call.has_prefix("read:")))
  authority.end_operation()
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "initial control HMAC refuses pending Crypto lifetime and cannot revive its observed custody" {
  let database = epoch_test_database("initial-control-library-current")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let (key, _, _) = read_epoch_custody(database).unwrap()
  let payload = b"control current DATA"
  let tag = crypto.hmac_sha256(key, payload).unwrap()
  let child = crypto.sha256_hasher().unwrap()
  authority.begin_operation(false)
  assert_true(
    authority.verify_control_payload_in_operation(payload, tag).unwrap(),
  )
  assert_true(crypto.close_checked() is Err(@crypto.CleanupPending))
  assert_true(
    authority.verify_control_payload_in_operation(payload, tag)
    is Err(Crypto(_)),
  )
  assert_true(authority.observed_custody is None)
  assert_true(
    authority.verify_control_payload_in_operation(payload, tag)
    is Err(Crypto(_)),
  )
  child.close_checked().unwrap()
  crypto.close_checked().unwrap()
  authority.end_operation()
  database.close_checked().unwrap()
}
