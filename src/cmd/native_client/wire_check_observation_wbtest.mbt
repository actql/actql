// Independent response fixtures; fixed pins come from the unchanged registered schema.

///|
test "Native submission check: original checked syntax" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511\",\"outcome_schema_cid\":\"sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), true)
}

///|
test "Native submission check: wrong reason pin" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"outcome_schema_cid\":\"sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: wrong outcome pin" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511\",\"outcome_schema_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: wrong scalar type" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511\",\"outcome_schema_cid\":\"sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":\"6\"}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}

///|
test "Native submission check: unknown input property" {
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"independent\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"},\"checkObservation\":{\"version\":\"actql-check-outcome/0.1\",\"reason_schema_cid\":\"sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511\",\"outcome_schema_cid\":\"sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6\",\"outcome\":\"completed\",\"report\":{\"context_ref\":\"ctx:independent\",\"scope\":{\"kind\":\"bound_input\"},\"verdict\":\"invalid\",\"runnable\":{\"verdict\":\"no\",\"reasons\":[{\"code\":\"query_syntax_invalid\"}]},\"inputs\":[{\"document_id\":\"source\",\"kind\":\"text\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"byte_length\":6,\"secret\":true}],\"reasons\":[{\"code\":\"query_syntax_invalid\",\"location\":{\"kind\":\"text\",\"document_id\":\"source\",\"revision\":\"rev:4444444444444444444444444444444444444444444444444444444444444444\",\"start_byte\":6,\"end_byte\":6,\"precision\":\"exact\"}}],\"requirements\":[],\"coverage\":{\"limits\":[],\"unresolved\":[]}}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_outcome_shape(value), false)
}
