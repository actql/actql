///|
test "Request snapshot grows the same original only on expansion and keeps its debit through query parse" {
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
  let base = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let before = calls.val
  reserve_request_snapshot(parent, input, 100L).unwrap()
  assert_eq(calls.val - before, 1)
  reserve_request_snapshot(parent, input, 100L).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(
    reserve_request_snapshot(parent, [1], 200L) is Err(ForeignOriginal),
  )
  let held = request_snapshot_data_bytes(100L).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input).unwrap(),
    (base.0 + held, base.1 + held),
  )
  let query = parse_request_query_syntax(
    parent,
    input,
    "SELECT 1 AS n",
    @frontend.Sql,
  ).unwrap()
  assert_true(
    physical_equal(prepared_request_query_syntax(parent, input).unwrap(), query),
  )
  assert_true(reserve_request_snapshot(parent, input, 200L) is Err(WrongPhase))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request snapshot short expansion retains its same high water until original cleanup" {
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    reserve_request_snapshot(parent, input, 10L).unwrap()
    let base = parent.snapshot_base.unwrap()
    let bytes = request_snapshot_data_bytes(20L).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.0 - bytes + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.1 - bytes + 1L
      },
    ).unwrap()
    assert_true(
      reserve_request_snapshot(parent, input, 20L) is Err(Capacity(_)),
    )
    assert_eq(parent.snapshot_units, 10L)
    assert_true(parent.phase == Open)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    reserve_request_snapshot(parent, input, 20L).unwrap()
    assert_eq(parent.snapshot_units, 20L)
    assert_true(reserve_request_snapshot(parent, input, 10L) is Err(Policy))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
