///|
// Actual original managed Resource callbacks/capacity, with explicit input
// DATA. No filesystem, Native frame, transport, Account or normal claim.
test "Native intake grows one original Request debit and observes current once per boundary" {
  let input = [1]
  let calls = Ref(0)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      calls.val += 1
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let capacity = parent.capacity
  let before_calls = calls.val
  reserve_request_native_intake_wire(parent, input, 65536).unwrap()
  assert_eq(calls.val - before_calls, 1)
  let base = parent.native_intake_base.unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(before.reserved_retention_bytes > base.0)
  assert_true(before.reserved_execution_bytes > base.1)
  assert_true(parent.submitted_intent is None && !parent.intent_attempted)
  let before_calls = calls.val
  reserve_request_native_intake_wire(parent, input, 65536).unwrap()
  assert_eq(calls.val - before_calls, 1)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  reserve_request_native_intake_wire(parent, input, 131072).unwrap()
  assert_true(physical_equal(parent.capacity, capacity))
  assert_eq(parent.native_intake_base, Some(base))
  assert_eq(parent.native_intake_wire_bytes, 131072)
  assert_eq(
    @resources.ledger_usage(parent.ledger).live_reservations,
    before.live_reservations,
  )
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, before.attempts)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Native intake refuses foreign decreasing and retired inputs without another constructor debit" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    reserve_request_native_intake_wire(parent, [1], 65536)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  reserve_request_native_intake_wire(parent, input, 65536).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    reserve_request_native_intake_wire(parent, input, 32768) is Err(WrongPhase),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    reserve_request_native_intake_wire(parent, input, 65536) is Err(WrongPhase),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Native intake current reentry and later denial preserve the same pending parent" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let allowed = Ref(true)
  let attempted = Ref(false)
  let refused = Ref(false)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if armed.val && !attempted.val {
        attempted.val = true
        let parent = selected.val.unwrap()
        refused.val = reserve_request_native_intake_wire(parent, input, 131072)
          is Err(WrongPhase) &&
          abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
      }
      allowed.val
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(parent)
  armed.val = true
  reserve_request_native_intake_wire(parent, input, 65536).unwrap()
  assert_true(attempted.val && refused.val)
  let before = @resources.ledger_usage(parent.ledger)
  allowed.val = false
  assert_true(
    reserve_request_native_intake_wire(parent, input, 65536) is Err(Capacity(_)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(parent.phase == Open && parent.input is Some(_))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
