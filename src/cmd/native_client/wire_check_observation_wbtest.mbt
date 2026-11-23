// Independent response fixtures; fixed pins come from the unchanged registered schema.

///|
test "Native submission check: original checked syntax" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:a2bf0f2824052a62a9b501094edd89888c8a5b1ce9530c5d28a6dcee33ce816f\",\"outcome_schema_cid\":\"sha256:12497b50d1f2a20ef355b6a3a59ae497bd8dd86ebaca33797ed47af4e2f08423\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), true)
}

///|
test "Native submission check: wrong reason pin" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"outcome_schema_cid\":\"sha256:12497b50d1f2a20ef355b6a3a59ae497bd8dd86ebaca33797ed47af4e2f08423\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: wrong outcome pin" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:a2bf0f2824052a62a9b501094edd89888c8a5b1ce9530c5d28a6dcee33ce816f\",\"outcome_schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: wrong scalar type" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:a2bf0f2824052a62a9b501094edd89888c8a5b1ce9530c5d28a6dcee33ce816f\",\"outcome_schema_cid\":\"sha256:12497b50d1f2a20ef355b6a3a59ae497bd8dd86ebaca33797ed47af4e2f08423\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":\"6\"}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: unknown input property" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:a2bf0f2824052a62a9b501094edd89888c8a5b1ce9530c5d28a6dcee33ce816f\",\"outcome_schema_cid\":\"sha256:12497b50d1f2a20ef355b6a3a59ae497bd8dd86ebaca33797ed47af4e2f08423\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6,\"secret\":true}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}
