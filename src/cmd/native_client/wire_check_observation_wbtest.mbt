// Independent response fixtures; fixed pins come from the unchanged registered schema.

///|
test "Native submission check: original checked syntax" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a\",\"outcome_schema_cid\":\"sha256:dbc59a5b3911315f28f04a4eb93808f56a85338cdb514c4a0546fedff0f1d6c9\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), true)
}

///|
test "Native submission check: wrong reason pin" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"outcome_schema_cid\":\"sha256:dbc59a5b3911315f28f04a4eb93808f56a85338cdb514c4a0546fedff0f1d6c9\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: wrong outcome pin" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a\",\"outcome_schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: wrong scalar type" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a\",\"outcome_schema_cid\":\"sha256:dbc59a5b3911315f28f04a4eb93808f56a85338cdb514c4a0546fedff0f1d6c9\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":\"6\"}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: unknown input property" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a\",\"outcome_schema_cid\":\"sha256:dbc59a5b3911315f28f04a4eb93808f56a85338cdb514c4a0546fedff0f1d6c9\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6,\"secret\":true}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}
