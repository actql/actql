///|
// A shape-admitted reference fixture is not authenticated Host/epoch custody.
fn cli_nonce_reference(
  nonce : String,
) -> @local_host.NativeClientSubmissionReference raise ClientStop {
  let epoch = Json::object(
    Map([
      ("version", Json::string("actql-submission-epoch/0.1")),
      ("authorityScopeCid", Json::string("sha256:" + "a".repeat(64))),
      ("epochNonce", Json::string("b".repeat(64))),
      ("notBefore", Json::number(1000.0)),
      ("expiresAt", Json::number(2000.0)),
      ("authenticator", Json::string("0".repeat(64))),
    ]),
  )
  @local_host.admit_native_client_submission_reference(
    encode_request_json(
      Json::object(Map([("epoch", epoch), ("nonce", Json::string(nonce))])),
      4096,
    ),
  ).unwrap()
}

///|
test "Local submission asserts the saved nonce without changing the original derived identity" {
  let reference = cli_nonce_reference("installed-select-1")
  let original_wire = @local_host.native_client_submission_reference_wire(
    reference,
  )
  let original_id = @local_host.native_client_submission_request_id(reference)
  assert_true(original_id != "installed-select-1")
  assert_true(
    local_submission_nonce_matches(reference, Some("installed-select-1")),
  )
  assert_true(local_submission_nonce_matches(reference, None))
  assert_false(
    local_submission_nonce_matches(reference, Some("different-nonce")),
  )
  assert_false(local_submission_nonce_matches(reference, Some(original_id)))
  assert_eq(
    @local_host.native_client_submission_reference_wire(reference),
    original_wire,
  )
  assert_eq(
    @local_host.native_client_submission_request_id(reference),
    original_id,
  )
}

///|
test "Local nonce assertion remains bound to the Owner-admitted original reference" {
  let first = cli_nonce_reference("first")
  let second = cli_nonce_reference("second")
  assert_true(local_submission_nonce_matches(first, Some("first")))
  assert_false(local_submission_nonce_matches(second, Some("first")))
  assert_true(local_submission_nonce_matches(second, Some("second")))
  assert_true(
    @local_host.native_client_submission_request_id(first) !=
    @local_host.native_client_submission_request_id(second),
  )
}
