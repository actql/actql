///|
fn assert_lookup_execution_fixture(
  body : String,
  expected : String,
  accepted : Bool,
) -> Unit raise {
  let profile = "{\"lookup_execution\":" + body + "}"
  let environment = capacity_wire(profile)
  let limits : LookupExecutionLimits = { max_work: 10000, max_bytes: 10000, }
  let outcome = check_lookup_execution(environment, limits)
  if !accepted {
    guard outcome is Err(issue) else { fail("invalid policy accepted") }
    assert_eq(issue.kind, InvalidComponent)
    assert_true(issue.source is Some(_))
    return
  }
  let checked = outcome.unwrap()
  let policy = lookup_execution_policy(checked).unwrap()
  assert_true(
    physical_equal(lookup_execution_environment(checked), environment),
  )
  assert_eq(lookup_execution_cid(policy), expected)
  assert_true(expected != cid(environment))
  let other = capacity_wire(profile)
  assert_false(physical_equal(lookup_execution_environment(checked), other))
  let object = @decode.open_object(lookup_execution_source(policy)).unwrap()
  for
    (name, field) in [
      (
        "max_network_attempts_per_request",
        LookupExecutionCeiling::NetworkAttemptsPerRequest,
      ),
      ("max_request_bytes_per_attempt", RequestBytesPerAttempt),
      ("max_total_request_bytes", TotalRequestBytes),
      ("max_total_response_bytes", TotalResponseWireBytes),
      ("max_total_decoded_response_bytes", TotalResponseDecodedBytes),
      ("max_total_duration_ms", TotalDurationMs),
    ] {
    assert_eq(
      lookup_execution_ceiling(policy, field),
      @decode.safe_integer(@decode.lookup(object, name).unwrap()).unwrap(),
    )
  }
  let (work, bytes) = lookup_execution_usage(checked)
  assert_eq(bytes, body.length())
  let exact : LookupExecutionLimits = { max_work: work, max_bytes: bytes, }
  assert_true(check_lookup_execution(environment, exact) is Ok(_))
  assert_true(
    check_lookup_execution(environment, { ..exact, max_work: work - 1, })
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    check_lookup_execution(environment, { ..exact, max_bytes: bytes - 1, })
    is Err({ kind: ByteLimit, .. }),
  )
}

///|
test "lookup execution absence remains owned and metered without defaults" {
  let environment = capacity_wire("{\"opaque\":{\"lookup_execution\":null}}")
  let checked = check_lookup_execution(environment, {
    max_work: 7,
    max_bytes: 0,
  }).unwrap()
  assert_true(lookup_execution_policy(checked) is None)
  assert_eq(lookup_execution_usage(checked), (7, 0))
  assert_true(
    physical_equal(lookup_execution_environment(checked), environment),
  )
  assert_true(
    check_lookup_execution(environment, { max_work: 6, max_bytes: 0, })
    is Err({ kind: WorkLimit, .. }),
  )
  let empty = check_lookup_execution(capacity_wire("{}"), {
    max_work: 0,
    max_bytes: 0,
  }).unwrap()
  assert_true(lookup_execution_policy(empty) is None)
  for
    limits in [
      LookupExecutionLimits::{ max_work: -1, max_bytes: 0, },
      { max_work: 0, max_bytes: -1, },
    ] {
    assert_true(
      check_lookup_execution(environment, limits)
      is Err({ kind: InvalidLimits, source: None, }),
    )
  }
}
