///|
test "HTTP input reserves actual long Text geometry on the same Request without fake snapshot nodes" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let capacity = owner.capacity
  let wire = "{\"text\":\"" + "x".repeat(10000) + "\"}"
  reserve_request_http_input(owner, input, wire.length(), 16, 1024, 65536).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  prepare_request_http_json(owner, input, wire).unwrap()
  let after = @resources.ledger_usage(owner.ledger)
  // Two observed nodes; raw key4 + Text10000. The existing native snapshot
  // representation law is 2H/4R/2W per node and8 UTF16 units per observed unit.
  let tree = 16L * 4L + 8L * 8L + 8L * 4L + 2L * 8L * 10006L
  assert_eq(
    after.reserved_retention_bytes - before.reserved_retention_bytes,
    tree,
  )
  assert_eq(
    after.reserved_execution_bytes - before.reserved_execution_bytes,
    tree,
  )
  assert_true(physical_equal(owner.capacity, capacity))
  assert_eq(owner.snapshot_units, 0L)
  assert_eq(owner.snapshot_values, 0L)
  assert_eq(request_preparation_work_calls(owner), (0L, 0L, 0L, 0L))
  assert_true(owner.submitted_intent is None && owner.program_json is None)
  assert_true(prepare_request_http_json(owner, input, wire) is Err(WrongPhase))
  // Later original SDK admission keeps its existing phase order.
  let next = @resources.begin_preparation_phase_work64(
    capacity,
    input,
    @resources.HeaderInspection,
    0L,
  ).unwrap()
  @resources.finish_preparation_phase_work64(next).unwrap() |> ignore
  reserve_request_snapshot(owner, input, 8L, 2L).unwrap()
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "HTTP input preserves original wire policy foreign current and failed growth cleanup" {
  let input = [1]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  assert_true(
    reserve_request_http_input(owner, [1], 64, 1, 64, 65536)
    is Err(ForeignOriginal),
  )
  reserve_request_http_input(owner, input, 64, 1, 64, 65536).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_http_input(owner, input, 64, 1, 64, 65535)
    is Err(WrongPhase),
  )
  assert_true(
    reserve_request_http_input(owner, input, 63, 1, 64, 65536)
    is Err(WrongPhase),
  )
  assert_true(
    reserve_request_http_input(owner, input, 64, 1, 63, 65536)
    is Err(WrongPhase),
  )
  assert_true(
    reserve_request_http_input(owner, input, 65538, 1, 64, 65536) is Err(Policy),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  current.val = false
  assert_true(
    reserve_request_http_input(owner, input, 128, 2, 64, 65536)
    is Err(Capacity(_)),
  )
  assert_eq(owner.http_input.unwrap().wire, 64)
  assert_true(
    prepare_request_http_json(owner, [1], "{}") is Err(ForeignOriginal),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "HTTP native tree refuses a smaller original parent before construction and retains cleanup" {
  let input = [1]
  let policy = client_local_resource_policy()
  let limits = client_local_preparation_initial_limits(
    policy,
    retained_bytes=Some(100000L),
    execution_bytes=Some(100000L),
  ).unwrap()
  let owner = begin_request_preparation(
    request_parent_fixture(input, initial_limits=Some(limits)),
    input,
    policy,
  ).unwrap()
  let original = owner.capacity
  let wire = "{\"text\":\"" + "x".repeat(10000) + "\"}"
  reserve_request_http_input(owner, input, wire.length(), 1, 1024, 65536).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(prepare_request_http_json(owner, input, wire) is Err(Capacity(_)))
  let after = @resources.ledger_usage(owner.ledger)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(physical_equal(original, owner.capacity))
  assert_true(owner.http_input.unwrap().work is None)
  assert_true(owner.program_json is None && owner.submitted_intent is None)
  assert_eq(request_preparation_work_calls(owner), (0L, 0L, 0L, 0L))
  assert_true(prepare_request_http_json(owner, input, wire) is Err(WrongPhase))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}
