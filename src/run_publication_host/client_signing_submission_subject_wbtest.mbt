///|
// These public-token/record fixtures prove identity laws and nominal joins
// only. The tag is not authenticated here; Native journal/HMAC/current and
// actual paired-capture/claim/signing acceptance remain separate.
test "Signing Submission identity distinguishes two nonces within one epoch" {
  let token = admit_client_submission_epoch_token(original_submission_token).unwrap()
  let original = prepare_client_submission_reference_record(
    token, "original-submit",
  ).unwrap()
  let other = prepare_client_submission_reference_record(token, "second-submit").unwrap()
  // Independent literal epoch/identity preimages hashed with Python hashlib.
  assert_eq(
    client_submission_reference_record_request_id(original),
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
  assert_eq(
    client_submission_reference_record_request_id(other),
    "sha256:536fad8223f3f48fadb69b12b1a3876792dcfb4c1824b9196b1e6c0c73b5e6c9",
  )
  assert_true(original.request_id != other.request_id)
  assert_eq(
    submission_epoch_cid(original.epoch.body),
    submission_epoch_cid(other.epoch.body),
  )
  assert_true(original.request_id != submission_epoch_cid(token.body))
}

///|
test "Signing Submission identity distinguishes epochs and is not renewed by history inspection" {
  let token = admit_client_submission_epoch_token(original_submission_token).unwrap()
  let other_token = admit_client_submission_epoch_token(
    original_submission_token.replace(
      old="\"epochNonce\":\"" + "b".repeat(64) + "\"",
      new="\"epochNonce\":\"" + "d".repeat(64) + "\"",
    ),
  ).unwrap()
  let original = prepare_client_submission_reference_record(
    token, "original-submit",
  ).unwrap()
  let other = prepare_client_submission_reference_record(
    other_token, "original-submit",
  ).unwrap()
  assert_eq(
    submission_epoch_cid(other_token.body),
    "sha256:a0d6489a798895c31edacd8de0379e78825658354452e5029ba195324a59ed27",
  )
  assert_eq(
    other.request_id,
    "sha256:2c959b03fc841b7ad0d32d7216e71416e9270a829d7533f4f652779a7189422c",
  )
  assert_true(original.request_id != other.request_id)
  assert_eq(original.epoch.authority_scope_cid, other.epoch.authority_scope_cid)
  assert_eq(
    submission_epoch_validity(token.body, 2000.0).unwrap(),
    @request_scope.Expired,
  )
  assert_eq(
    admit_client_submission_reference_record(original.wire).unwrap().request_id,
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
  // Parsing the same expired historical identity neither creates an epoch
  // nor claims that the caller may start or sign anything.
  assert_eq(
    submission_epoch_validity(token.body, 2000.0).unwrap(),
    @request_scope.Expired,
  )
}

///|
test "Signing Submission join refuses a foreign retained Run and another nonce" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let admission = record.run_admission.unwrap()
  let definition = saved_submission_definition()
  assert_true(
    validate_client_submitted_retained_run(
      record.reference,
      admission,
      admission.0,
      definition,
      9007199254740994L,
    )
    is Ok(_),
  )
  assert_true(
    validate_client_submitted_retained_run(
      record.reference,
      (admission.0, "sha256:" + "e".repeat(64), admission.2),
      admission.0,
      definition,
      9007199254740994L,
    )
    is Err(CustodyLost),
  )
  let token = admit_client_submission_epoch_token(original_submission_token).unwrap()
  let other = prepare_client_submission_reference_record(token, "second-submit").unwrap()
  assert_true(
    validate_client_submitted_retained_run(
      other,
      admission,
      admission.0,
      definition,
      9007199254740994L,
    )
    is Err(CustodyLost),
  )
}

///|
test "Signing Submission and logical scopes remain separate and copied logical scope is refused" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let request = record.run_admission.unwrap().0
  assert_eq(
    client_request_scope_cid(request),
    "sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918",
  )
  assert_eq(
    record.reference.request_id,
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
  assert_true(record.reference.request_id != client_request_scope_cid(request))
  let wire = client_request_identity_record_wire(request).unwrap()
  let changed = wire.replace(
    old="\"logical_request_scope_cid\":\"sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918\"",
    new="\"logical_request_scope_cid\":\"sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267\"",
  )
  assert_true(changed != wire)
  assert_true(
    admit_client_request_identity_record_wire(changed) is Err(IdentityMismatch),
  )
}
