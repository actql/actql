///|
/// Exact typed request retention only; these values issue no stop/release ACK.
test "relayed release keeps the original request and deduplicates replay" {
  let original = holder_custody_test_request("source", "source-attempt")
  let consumer = holder_custody_test_request("consumer", "consumer-attempt")
  let retained : Map[String, @remote.DispatchRequest] = Map([])
  assert_true(remember_holder_release(original, retained, original, 2))
  assert_true(remember_holder_release(original, retained, consumer, 2))
  assert_true(remember_holder_release(original, retained, original, 2))
  assert_eq(retained.size(), 2)
  assert_true(
    physical_equal(
      retained.get(@remote.dispatch_request_identity(original)).unwrap(),
      original,
    ),
  )
  assert_true(
    physical_equal(
      retained.get(@remote.dispatch_request_identity(consumer)).unwrap(),
      consumer,
    ),
  )
}

///|
test "retention refusal cannot replace a prior delivered release" {
  let original = holder_custody_test_request("source", "source-attempt")
  let consumer = holder_custody_test_request("consumer", "consumer-attempt")
  let retained : Map[String, @remote.DispatchRequest] = Map([])
  assert_true(remember_holder_release(original, retained, original, 1))
  assert_false(remember_holder_release(original, retained, consumer, 1))
  assert_eq(retained.size(), 1)
  assert_true(
    physical_equal(
      retained.get(@remote.dispatch_request_identity(original)).unwrap(),
      original,
    ),
  )
}
