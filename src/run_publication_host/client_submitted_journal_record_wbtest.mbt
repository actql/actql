///|
// Independently fixed original schema bodies and hashlib preimages. The
// epoch tag is a shape fixture; no HMAC, transaction or admission is asserted.
let saved_submission_preparing : String =
  #|{"intent":"{\"input\":{\"format\":\"sql\",\"text\":\"/*😀*/\\r\\nSELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":{\"é/~\":null,\"é\":{\"missing\":{}}}}","phase":"preparing","reference":"{\"epoch\":{\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"authorityScopeCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"expiresAt\":2000,\"notBefore\":1000,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-submit\"}","version":"actql-native-client-submitted-intent-row/0.1"}

///|
let saved_submission_ready : String =
  #|{"intent":"{\"input\":{\"format\":\"sql\",\"text\":\"/*😀*/\\r\\nSELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":{\"é/~\":null,\"é\":{\"missing\":{}}}}","phase":"ready","reference":"{\"epoch\":{\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"authorityScopeCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"expiresAt\":2000,\"notBefore\":1000,\"version\":\"actql-submission-epoch/0.1\"},\"nonce\":\"original-submit\"}","run_admission":"{\"admitted_revision\":\"9007199254740993\",\"request\":\"{\\\"authority_scope_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"run_definition_cid\":\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\"}","version":"actql-native-client-submitted-intent-row/0.1"}

///|
let saved_submission_intent : String =
  #|{"input":{"format":"sql","text":"/*😀*/\r\nSELECT 1 AS n"},"kind":"aql","parameters":{"é/~":null,"é":{"missing":{}}}}

///|
let saved_submission_changed_request : String =
  #|{"authority_scope_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","caller_input_intent_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","caller_request_id":"sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267","intent_fingerprint_cid":"sha256:ce29d331b79bd01199540b4d79b96cc8f3801c85c75d732a57762f337c441b6c","logical_request_scope_cid":"sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918","parameter_values_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","program_definition_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}

///|
let saved_submission_other_request : String =
  #|{"authority_scope_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","caller_input_intent_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","caller_request_id":"other-request","intent_fingerprint_cid":"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010","logical_request_scope_cid":"sha256:ae51162e2a76abe548e49e88e6b359735e8631bc6a49e79d7cfad0dba3211509","parameter_values_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","program_definition_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}

///|
let saved_submission_scope_request : String =
  #|{"authority_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","caller_input_intent_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","caller_request_id":"sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267","intent_fingerprint_cid":"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010","logical_request_scope_cid":"sha256:e6d257032804fb5460539548f75930e338aa19922b4816e81aaeb4214ddc3ab6","parameter_values_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","program_definition_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}

///|
let saved_submission_intent_cid : String = "sha256:32e181c7ce95233f798efa97ebef5aa737619874e9abfe60ea86a44b069ba33f"

///|
fn saved_submission_definition() -> @publication.PublicationContract {
  @publication.admit_publication_contract(
    "run_definition", journal_encoding_definition, 65536, 4096, 64,
  ).unwrap()
}

///|
test "original saved preparing row preserves independent input identity without Run admission" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_preparing),
  ).unwrap()
  assert_eq(
    client_submission_reference_record_request_id(record.reference),
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
  assert_eq(
    client_submitted_intent_wire(record.intent),
    saved_submission_intent,
  )
  assert_eq(
    client_submitted_intent_cid(record.intent),
    saved_submission_intent_cid,
  )
  assert_true(record.run_admission is None)
}

///|
test "original saved ready row retains exact Int64 revision and original intent" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  guard record.run_admission is Some((request, definition, revision)) else {
    fail("Expected original admission fields")
  }
  assert_eq(revision, 9007199254740993L)
  assert_eq(
    client_request_scope_cid(request),
    "sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918",
  )
  assert_eq(
    definition, "sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc",
  )
  // NULL, missing values, decomposed/composed keys, emoji and CRLF are raw
  // submitted values. Decoding this row neither checks nor executes its SQL.
  assert_eq(
    client_submitted_intent_wire(record.intent),
    saved_submission_intent,
  )
  assert_eq(
    client_submitted_intent_cid(record.intent),
    saved_submission_intent_cid,
  )
}

///|
test "saved submitted row rejects unknown duplicate missing NULL and invalid phases" {
  for
    wire in [
      "null",
      "{}",
      saved_submission_preparing.replace(old="{", new="{\"accepted\":true,"),
      saved_submission_preparing.replace(
        old="\"phase\":\"preparing\"",
        new="\"phase\":\"preparing\",\"phase\":\"ready\"",
      ),
      saved_submission_preparing.replace(
        old="\"phase\":\"preparing\"",
        new="\"phase\":\"ready\"",
      ),
      saved_submission_ready.replace(
        old="\"phase\":\"ready\"",
        new="\"phase\":\"preparing\"",
      ),
      saved_submission_preparing.replace(
        old="\"phase\":\"preparing\"",
        new="\"phase\":\"held\"",
      ),
      saved_submission_preparing.replace(old="\"phase\":\"preparing\",", new=""),
      saved_submission_preparing.replace(
        old="\"phase\":\"preparing\"",
        new="\"phase\":null",
      ),
      saved_submission_preparing.replace(
        old="\"phase\":\"preparing\"",
        new="\"phase\":\"preparing\",\"run_admission\":null",
      ),
      saved_submission_preparing.replace(
        old="actql-native-client-submitted-intent-row/0.1",
        new="actql-native-client-submitted-intent-row/0.2",
      ),
    ] {
    assert_true(
      decode_client_submitted_journal_row(@utf8.encode(wire))
      is Err(CustodyLost),
    )
  }
}

///|
test "saved submitted row refuses forged reference request and canonical bytes" {
  for
    wire in [
      " " + saved_submission_ready,
      saved_submission_ready.replace(old="{", new="{ "),
      saved_submission_ready.replace(old="47ab54e0ad7e", new="000000000000"),
      saved_submission_ready.replace(old="585c858537f5", new="000000000000"),
      saved_submission_ready.replace(
        old="actql-submission-epoch/0.1",
        new="actql-submission-epoch/0.2",
      ),
      saved_submission_ready.replace(
        old="\\\"9007199254740993\\\"",
        new="9007199254740993",
      ),
      saved_submission_ready.replace(
        old="\\\"9007199254740993\\\"",
        new="\\\"-1\\\"",
      ),
    ] {
    assert_true(
      decode_client_submitted_journal_row(@utf8.encode(wire))
      is Err(CustodyLost),
    )
  }
}

///|
test "saved submitted row decoder keeps original UTF8 and input byte caps" {
  assert_true(decode_client_submitted_journal_row(b"\xff") is Err(CustodyLost))
  assert_true(
    decode_client_submitted_journal_row(@utf8.encode("x".repeat(262145)))
    is Err(CustodyLost),
  )
  // The independently fixed original intent becomes larger than the same
  // 65536-byte limit. Its enclosing row still fits the original row profile.
  let wire = saved_submission_preparing.replace(
    old="SELECT 1 AS n",
    new="x".repeat(65536),
  )
  assert_true(
    decode_client_submitted_journal_row(@utf8.encode(wire)) is Err(CustodyLost),
  )
}

///|
test "original retained admission accepts equal or later revision without reissuing it" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  guard record.run_admission is Some(admission) else {
    fail("Expected original admission")
  }
  // An expired epoch may identify old retained history; this relationship
  // validator grants no fresh admission, start or resend permission.
  assert_true(
    submission_epoch_validity(
      client_submission_epoch_token_body(
        client_submission_reference_record_epoch(record.reference),
      ),
      2000.0,
    )
    is Ok(@request_scope.Expired),
  )
  for revision in [9007199254740993L, 9007199254740994L, 9223372036854775807L] {
    assert_true(
      validate_client_submitted_retained_run(
        record.reference,
        admission,
        admission.0,
        saved_submission_definition(),
        revision,
      )
      is Ok(_),
    )
  }
  assert_eq(admission.2, 9007199254740993L)
}

///|
test "retained admission refuses earlier revision foreign request and changed intent" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  guard record.run_admission is Some(admission) else {
    fail("Expected original admission")
  }
  for
    wire in [
      saved_submission_changed_request, saved_submission_other_request, saved_submission_scope_request,
    ] {
    let retained = admit_client_request_identity_record_wire(wire).unwrap()
    assert_true(
      validate_client_submitted_retained_run(
        record.reference,
        admission,
        retained,
        saved_submission_definition(),
        9223372036854775807L,
      )
      is Err(CustodyLost),
    )
  }
  for revision in [-1L, 0L, 9007199254740992L] {
    assert_true(
      validate_client_submitted_retained_run(
        record.reference,
        admission,
        admission.0,
        saved_submission_definition(),
        revision,
      )
      is Err(CustodyLost),
    )
  }
  assert_true(
    validate_client_submitted_retained_run(
      record.reference,
      (admission.0, admission.1, -1L),
      admission.0,
      saved_submission_definition(),
      9223372036854775807L,
    )
    is Err(CustodyLost),
  )
}

///|
test "retained admission refuses foreign Reference and Run Definition" {
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  guard record.run_admission is Some(admission) else {
    fail("Expected original admission")
  }
  let foreign_reference = admit_client_submission_reference_record(
    client_submission_reference_record_wire(record.reference).replace(
      old="original-submit",
      new="other-submit",
    ),
  ).unwrap()
  assert_true(
    validate_client_submitted_retained_run(
      foreign_reference,
      admission,
      admission.0,
      saved_submission_definition(),
      9223372036854775807L,
    )
    is Err(CustodyLost),
  )
  assert_true(
    validate_client_submitted_retained_run(
      record.reference,
      (admission.0, "sha256:" + "e".repeat(64), admission.2),
      admission.0,
      saved_submission_definition(),
      9223372036854775807L,
    )
    is Err(CustodyLost),
  )
}

///|
test "observed submitted row restores large original intent and preserves canonical refusal" {
  let original = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_preparing),
  ).unwrap()
  let wire = "{\"input\":{\"text\":\"" +
    "x".repeat(300000) +
    "\"},\"kind\":\"aql\",\"parameters\":null}"
  let intent = prepare_client_submitted_intent(wire, 400000, 64, 8).unwrap()
  let reference = client_submission_reference_record_wire(original.reference)
  // Explicit source-only construction scope. No Native allocator, Read grow,
  // physical transaction or Saved runtime is substituted by this fixture.
  let body = client_submitted_intent_journal_row_body(
    reference,
    intent,
    before_construction=Some((_, _, _) => Ok(())),
  ).unwrap()
  assert_true(body.length() > 262144)
  assert_true(decode_client_submitted_journal_row(body) is Err(CustodyLost))
  let decoded = decode_client_submitted_journal_row_profile(body, true).unwrap()
  assert_eq(client_submitted_intent_wire(decoded.intent), wire)
  assert_eq(
    client_submitted_intent_cid(decoded.intent),
    client_submitted_intent_cid(intent),
  )
  assert_eq(decoded.intent.wire_bytes, intent.wire_bytes)
  assert_eq(
    client_submission_reference_record_wire(decoded.reference),
    reference,
  )
  assert_true(decoded.run_admission is None)
  let text = @utf8.decode(body)
  for
    invalid in [
      " " + text,
      text.replace(old="\"phase\":\"preparing\"", new="\"phase\":null"),
      text.replace(
        old="\"phase\":\"preparing\"",
        new="\"phase\":\"preparing\",\"phase\":\"ready\"",
      ),
      text.replace(
        old="actql-native-client-submitted-intent-row/0.1",
        new="foreign-client-submitted-intent-row/0.1",
      ),
    ] {
    assert_true(
      decode_client_submitted_journal_row_profile(@utf8.encode(invalid), true)
      is Err(CustodyLost),
    )
  }
}

///|
test "observed submitted row keeps nonintent string profile unchanged" {
  let original = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let body = client_submitted_intent_journal_row_body(
    client_submission_reference_record_wire(original.reference),
    original.intent,
    run_admission=original.run_admission,
    run_state_original=Some("{}"),
    run_state_observation=Some((1L, Some("x".repeat(131073)))),
    before_construction=Some((_, _, _) => Ok(())),
  ).unwrap()
  assert_true(
    decode_client_submitted_journal_row_profile(body, true) is Err(CustodyLost),
  )
}
