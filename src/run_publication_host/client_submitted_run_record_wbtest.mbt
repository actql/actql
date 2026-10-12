///|
// Independent canonical request/intent preimages were hashed with Python
// hashlib. The existing request Owner checks those fixed identity claims.
let submitted_run_record_fixture = "{\"admitted_revision\":\"9007199254740993\",\"request\":\"{\\\"authority_scope_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"caller-é\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"run_definition_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}"

///|
test "shared submitted admission codec preserves exact original bytes and Int64 revision" {
  let (request, definition, revision) = admit_client_submitted_run_admission_wire(
    submitted_run_record_fixture,
  ).unwrap()
  assert_eq(client_request_caller_id(request), "caller-é")
  assert_eq(definition, "sha256:" + "e".repeat(64))
  assert_eq(revision, 9007199254740993L)
  assert_eq(
    client_submitted_run_admission_wire(request, definition, revision).unwrap(),
    submitted_run_record_fixture,
  )
}

///|
test "shared submitted admission codec refuses malformed noncanonical and foreign identity records" {
  for
    wire in [
      submitted_run_record_fixture + " ",
      submitted_run_record_fixture.replace(
        old="{\"admitted_revision\":",
        new="{\"extra\":true,\"admitted_revision\":",
      ),
      submitted_run_record_fixture.replace(
        old="{\"admitted_revision\":",
        new="{\"admitted_revision\":\"0\",\"admitted_revision\":",
      ),
      submitted_run_record_fixture.replace(
        old="\"9007199254740993\"",
        new="9007199254740993",
      ),
      submitted_run_record_fixture.replace(
        old="\"9007199254740993\"",
        new="null",
      ),
      submitted_run_record_fixture.replace(
        old="\"9007199254740993\"",
        new="\"-1\"",
      ),
      submitted_run_record_fixture.replace(
        old="\"9007199254740993\"",
        new="\"9223372036854775808\"",
      ),
      submitted_run_record_fixture.replace(old="caller-é", new="caller-other"),
      " ".repeat(8193),
    ] {
    assert_eq(admit_client_submitted_run_admission_wire(wire), Err(CustodyLost))
  }
}

///|
test "shared submitted admission codec retains zero and maximal original revisions" {
  for
    (text, revision) in [
      ("0", 0L),
      ("9223372036854775807", 9223372036854775807L),
    ] {
    let original = submitted_run_record_fixture.replace(
      old="9007199254740993",
      new=text,
    )
    let (request, definition, actual) = admit_client_submitted_run_admission_wire(
      original,
    ).unwrap()
    assert_eq(actual, revision)
    assert_eq(
      client_submitted_run_admission_wire(request, definition, actual).unwrap(),
      original,
    )
  }
}
