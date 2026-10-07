///|
test "submission epoch uses an independently specified body and half-open interval" {
  let epoch = prepare_submission_epoch(
    "sha256:" + "a".repeat(64),
    "b".repeat(64),
    1800000000000.0,
    1800000001000.0,
  ).unwrap()
  assert_eq(
    submission_epoch_cid(epoch),
    "sha256:864dc9b8f1f801ba4e70683c04a5a0e66146a9ec38e74d93797f8b1bf29d600a",
  )
  assert_eq(
    submission_request_id(epoch, "request-1"),
    Ok(
      "sha256:cdf4c7466562674bab239a1a938f6a8784cc9efc07472edeb5f3efe44d7e3c27",
    ),
  )
  assert_eq(
    submission_epoch_wire(epoch),
    "{\"authority_scope_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epoch_nonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"expires_at\":1800000001000,\"not_before\":1800000000000,\"version\":\"actql-submission-epoch/0.1\"}",
  )
  assert_eq(submission_epoch_validity(epoch, 1799999999999.0), Ok(NotYetValid))
  assert_eq(submission_epoch_validity(epoch, 1800000000000.0), Ok(Admissible))
  assert_eq(submission_epoch_validity(epoch, 1800000000999.0), Ok(Admissible))
  assert_eq(submission_epoch_validity(epoch, 1800000001000.0), Ok(Expired))
  assert_eq(submission_epoch_validity(epoch, 1800000002000.0), Ok(Expired))
  assert_eq(submission_epoch_validity(epoch, -1.0), Err(InvalidClock))
}

///|
test "submission identity preserves its epoch and validates the common nonce domain" {
  let epoch = prepare_submission_epoch(
    "sha256:" + "a".repeat(64),
    "b".repeat(64),
    1800000000000.0,
    1800000001000.0,
  ).unwrap()
  assert_eq(
    submission_request_id(epoch, "e\u{0301}"),
    Err(InvalidSubmissionNonce),
  )
  assert_eq(
    submission_request_id(epoch, "row\r\n"),
    Err(InvalidSubmissionNonce),
  )
  assert_true(submission_request_id(epoch, "é") is Ok(_))
  let other = prepare_submission_epoch(
    "sha256:" + "a".repeat(64),
    "c".repeat(64),
    1800000000000.0,
    1800000001000.0,
  ).unwrap()
  assert_true(
    submission_request_id(epoch, "request-1") !=
    submission_request_id(other, "request-1"),
  )
  assert_true(
    submission_request_id(epoch, "request-1") !=
    submission_request_id(epoch, "request-2"),
  )
}

///|
test "submission epoch rejects malformed authority nonce and intervals" {
  let scope = "sha256:" + "a".repeat(64)
  assert_true(
    prepare_submission_epoch("wrong", "b".repeat(64), 0.0, 1.0)
    is Err(InvalidAuthority),
  )
  assert_true(
    prepare_submission_epoch(scope, "B".repeat(64), 0.0, 1.0)
    is Err(InvalidEpochNonce),
  )
  assert_true(
    prepare_submission_epoch(scope, "b".repeat(63), 0.0, 1.0)
    is Err(InvalidEpochNonce),
  )
  for
    interval in [
      (1.0, 1.0),
      (2.0, 1.0),
      (-1.0, 1.0),
      (0.5, 1.0),
      (0.0, 9007199254740992.0),
    ] {
    assert_true(
      prepare_submission_epoch(scope, "b".repeat(64), interval.0, interval.1)
      is Err(InvalidInterval),
    )
  }
}
