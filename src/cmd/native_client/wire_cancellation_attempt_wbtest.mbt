// Independently authored operation-binding fixtures; expected results are not produced by a validator.

///|
test "Native cancellation attempt: accepted original invocation" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"accepted\",\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"},\"cancellation\":{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelRef\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"cancelId\":\"original-cancel\",\"expectedRevision\":19},\"kind\":\"accepted\",\"revision\":20}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), true)
}

///|
test "Native cancellation attempt: nonpersisted refusal" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"attempt_uncommitted_unconsumed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), true)
}

///|
test "Native cancellation attempt: revision conflict" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"conflict\",\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"},\"reason\":\"control_revision\",\"cancelRef\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"cancelId\":\"original-cancel\",\"expectedRevision\":19}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), true)
}

///|
test "Native cancellation attempt: foreign invocation" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"other-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"attempt_uncommitted_unconsumed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), false)
}

///|
test "Native cancellation attempt: foreign operation" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"submit\",\"attemptId\":\"original-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"attempt_uncommitted_unconsumed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), false)
}

///|
test "Native cancellation attempt: fabricated nonexecution guarantee" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"refused\",\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"},\"reason\":\"authorization\",\"guarantee\":\"nothing_executed\"}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), false)
}

///|
test "Native cancellation attempt: contradictory AlreadySatisfied" {
  let request = @utf8.encode(
    "{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelId\":\"original-cancel\",\"expectedRevision\":19,\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"}}",
  )
  let value = @json.parse(
    "{\"kind\":\"already_satisfied\",\"attemptRef\":{\"operation\":\"cancel\",\"attemptId\":\"original-invocation\"},\"cancellation\":{\"ref\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"cancelRef\":{\"namespaceId\":\"namespace-a\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"cancelId\":\"original-cancel\",\"expectedRevision\":19},\"kind\":\"accepted\",\"revision\":20}}",
  ) catch {
    _ => fail("InvalidIndependentFixture")
  }
  assert_eq(valid_cancellation_reply(value, request, false), false)
}
