// Independent fixtures for invocation and durable-original binding.

///|
test "Native Submission attempt: initial authorization refusal" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"attempt_uncommitted_unconsumed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), true)
}

///|
test "Native Submission attempt: intent conflict" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"conflict\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"reason\":\"intent\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), true)
}

///|
test "Native Submission attempt: durable NotAccepted" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"recorded\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"outcome\":{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), true)
}

///|
test "Native Submission attempt: raw durable receipt cannot replace this invocation" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), false)
}

///|
test "Native Submission attempt: foreign invocation" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"other-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"attempt_uncommitted_unconsumed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), false)
}

///|
test "Native Submission attempt: foreign original reference" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"recorded\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"outcome\":{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"other-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), false)
}

///|
test "Native Submission attempt: foreign submitted intent" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"recorded\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"outcome\":{\"kind\":\"not_accepted\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"problem\":{\"code\":\"ClientProgramInvalidInput\",\"classification\":\"invalid_input\"}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), false)
}

///|
test "Native Submission attempt: fabricated nonexecution guarantee" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"original_never_executed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), false)
}

///|
test "Native Submission attempt: contradictory AlreadySatisfied" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"already_satisfied\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"outcome\":{\"kind\":\"preparing\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(wire_submission_attempt_shape(value), false)
  assert_eq(valid_submission_reply(value, request, selected, false), false)
}

///|
test "Native Submission attempt: original ready receipt" {
  let request = @utf8.encode(
    "{\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"recorded\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"outcome\":{\"kind\":\"ready\",\"submissionRef\":{\"epoch\":{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"epochNonce\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"notBefore\":1800000000000,\"expiresAt\":1800000001000,\"authenticator\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},\"nonce\":\"original-submission\"},\"intentCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"admission\":{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"durability\":\"durable\",\"revision\":7}}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  let selected = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_submission_reply(value, request, selected, false), true)
}
