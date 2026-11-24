///|
test "Native named submission retains an earlier scoped original and refuses foreign replies" {
  let connection = @json.parse(
    (
      #|{"mode":"remote","owner":"remote","durability":"durable","consentRefs":[],"runners":[]}
    ),
  )
  let request = @json.parse(
    (
      #|{"requestName":"shared-query","submissionRef":{"epoch":{"version":"actql-submission-epoch/0.1","authorityScopeCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","epochNonce":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","authenticator":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","notBefore":2000,"expiresAt":3000},"nonce":"candidate"},"intentCid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","attemptRef":{"operation":"submit","attemptId":"this-attempt"}}
    ),
  )
  let response = @json.parse(
    (
      #|{"kind":"observed","requestName":"shared-query","intentCid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","attemptRef":{"operation":"submit","attemptId":"this-attempt"},"outcome":{"kind":"ready","submissionRef":{"epoch":{"version":"actql-submission-epoch/0.1","authorityScopeCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","epochNonce":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","authenticator":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","notBefore":1000,"expiresAt":2000},"nonce":"original"},"intentCid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","admission":{"ref":{"namespaceId":"workspace","authorityScopeCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","runDefinitionCid":"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},"durability":"durable","revision":0}}}
    ),
  )
  let request_wire = @utf8.encode(encode_request_json(request, 8192))
  assert_true(valid_named_submission_reply(response, request_wire, connection))
  let conflict = @json.parse(
    (
      #|{"kind":"conflict","requestName":"shared-query","intentCid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","attemptRef":{"operation":"submit","attemptId":"this-attempt"},"reason":"intent"}
    ),
  )
  assert_true(valid_named_submission_reply(conflict, request_wire, connection))
  guard response is Object(fields) &&
    fields.get("outcome") is Some(Object(outcome)) &&
    outcome.get("submissionRef") is Some(Object(original)) &&
    original.get("epoch") is Some(Object(epoch)) else {
    fail("invalid fixture")
  }
  let name = fields["requestName"]
  fields["requestName"] = Json::string("other-query")
  assert_false(valid_named_submission_reply(response, request_wire, connection))
  fields["requestName"] = name
  let attempt = fields["attemptRef"]
  fields["attemptRef"] = @json.parse(
    (
      #|{"operation":"submit","attemptId":"foreign-attempt"}
    ),
  )
  assert_false(valid_named_submission_reply(response, request_wire, connection))
  fields["attemptRef"] = attempt
  epoch["authorityScopeCid"] = Json::string(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  )
  assert_false(valid_named_submission_reply(response, request_wire, connection))
}

///|
test "Native named submission checks the same bounded caller name domain" {
  assert_true(valid_native_submission_name("é".repeat(128)))
  assert_false(valid_native_submission_name("é".repeat(129)))
  assert_false(valid_native_submission_name("e\u{0301}"))
  assert_false(valid_native_submission_name("before\u{0080}after"))
  assert_false(valid_native_submission_name("before\nafter"))
}
