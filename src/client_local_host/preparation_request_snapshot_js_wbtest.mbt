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
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  assert_eq(calls.val - before, 1)
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(
    reserve_request_snapshot(parent, [1], 200L, 200L) is Err(ForeignOriginal),
  )
  let held = request_snapshot_data_bytes(100L, 100L).unwrap()
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
  assert_true(
    reserve_request_snapshot(parent, input, 200L, 200L) is Err(WrongPhase),
  )
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
    reserve_request_snapshot(parent, input, 10L, 10L).unwrap()
    let base = parent.snapshot_base.unwrap()
    let bytes = request_snapshot_data_bytes(20L, 20L).unwrap()
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
    let refused = match reserve_request_snapshot(parent, input, 20L, 20L) {
      Err(SnapshotCapacityExceeded(original, value)) => {
        if retention {
          assert_true(original is Resource(RetentionLimit))
          assert_eq(value.dimension, "retention")
          assert_eq(value.required_retention, value.available_retention + 1L)
        } else {
          assert_true(original is Resource(ExecutionLimit))
          assert_eq(value.dimension, "execution")
          assert_eq(value.required_execution, value.available_execution + 1L)
        }
        value
      }
      _ => fail("Expected the original snapshot shortage and exact amounts")
    }
    assert_eq(refused.phase, "request_snapshot")
    assert_eq(parent.snapshot_units, 10L)
    assert_true(parent.phase == Open)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    reserve_request_snapshot(parent, input, 20L, 20L).unwrap()
    assert_eq(parent.snapshot_units, 20L)
    assert_true(
      reserve_request_snapshot(parent, input, 10L, 10L) is Err(Policy),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "authored document lower bound refuses a small Request before snapshot capture without spending its original" {
  // The existing collection fixture authors this exact finite SQL array.
  // Even its document alone exceeds the selected 32KiB; the complete SDK
  // envelope has additional values/keys. This is a lower bound, not a second
  // serializer, a future Plan maximum, or public submission evidence.
  let document = "SELECT [" + "0,".repeat(19999) + "0] AS cells"
  let units = document.length().to_int64()
  let memory = 32768L
  let policy = client_local_resource_policy()
  let (controls, _) = client_request_preparation_control_capacity(policy).unwrap()
  assert_true(controls < memory && memory < units)
  let lower_bound = request_snapshot_data_bytes(units, 1L).unwrap()
  for small in [true, false] {
    let selected = if small { memory } else { controls + lower_bound }
    let limits = client_local_preparation_initial_limits(
      policy,
      retained_bytes=Some(selected),
      execution_bytes=Some(selected),
    ).unwrap()
    let input = [1]
    let initial = request_parent_fixture(input, initial_limits=Some(limits))
    let parent = begin_request_preparation(initial, input, policy).unwrap()
    let before = @resources.ledger_usage(parent.ledger)
    let result = reserve_request_snapshot(parent, input, units, 1L)
    if small {
      let refusal = match result {
        Err(SnapshotCapacityExceeded(Resource(RetentionLimit), value)) => value
        _ => fail("Expected the original Resource retention shortage")
      }
      assert_eq(refusal.phase, "request_snapshot")
      assert_eq(refusal.dimension, "retention")
      assert_eq(refusal.required_retention, controls + lower_bound)
      assert_eq(refusal.required_execution, lower_bound)
      assert_eq(refusal.available_retention, memory)
      assert_eq(refusal.available_execution, memory)
      assert_eq(@resources.ledger_usage(parent.ledger), before)
      assert_eq(parent.snapshot_units, 0L)
      assert_eq(parent.snapshot_values, 0L)
    } else {
      result.unwrap()
      assert_eq(parent.snapshot_units, units)
      assert_eq(parent.snapshot_values, 1L)
      assert_eq(
        @resources.preparation_capacity_working_extents(parent.capacity, input).unwrap(),
        (controls + lower_bound, lower_bound),
      )
    }
    assert_true(parent.phase == Open && parent.query_syntax is None)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
