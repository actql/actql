///|
test "SDK expected wires remain per row while parse writer and comparison workspace stays serial" {
  let one = installed_node_model_sdk_v4_request_capacity(1, 32, 8, 4).unwrap()
  let two = installed_node_model_sdk_v4_request_capacity(2, 32, 8, 4).unwrap()
  // One String, isolated closure/context and two aliases; six escaped bytes
  // per original byte, two logical bytes per retained UTF16 unit.
  let row = 3L * 16L + 2L * 8L + 6L * 32L * 2L
  assert_eq(@execution.execution_capacity_retained_bytes(one), row)
  assert_eq(@execution.execution_capacity_retained_bytes(two), 2L * row)
  assert_eq(
    @execution.execution_capacity_execution_bytes(two) -
    @execution.execution_capacity_execution_bytes(one),
    row,
  )
  assert_true(@execution.execution_capacity_execution_bytes(one) > row)
  let r = @execution.execution_capacity_retained_bytes(two)
  let e = @execution.execution_capacity_execution_bytes(two)
  for shortage in [-1, 0, 1] {
    let ledger = @resources.create_ledger({
      planning_work: 1,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 0L,
      retained_bytes: r - (if shortage == 0 { 1L } else { 0L }),
      execution_bytes: e - (if shortage == 1 { 1L } else { 0L }),
    }).unwrap()
    let reserved = @resources.reserve_capacity(ledger, r, e)
    if shortage < 0 {
      @resources.settle_capacity(ledger, reserved.unwrap()).unwrap()
    } else {
      assert_true(reserved is Err(_))
    }
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  }
}

///|
test "SDK request construction refuses invalid dimensions and checked all row overflow" {
  assert_true(installed_node_model_sdk_v4_request_capacity(0, 32, 8, 4) is None)
  assert_true(installed_node_model_sdk_v4_request_capacity(1, 0, 8, 4) is None)
  assert_true(
    installed_node_model_sdk_v4_request_capacity(1, 357913942, 8, 4) is None,
  )
  assert_true(
    installed_node_model_sdk_v4_request_capacity(1, 32, 2147483647, 4) is None,
  )
  assert_true(
    installed_node_model_sdk_v4_request_capacity(1, 32, 8, 2147483647) is None,
  )
  assert_true(
    installed_node_model_sdk_v4_request_capacity(2147483647, 357913941, 8, 4)
    is None,
  )
}

///|
test "selected serial normal SDK request demand stays finite without changing the original ceiling" {
  let capacity = installed_node_model_sdk_v4_request_capacity(
    2, 32768, 4096, 32,
  ).unwrap()
  let r = @execution.execution_capacity_retained_bytes(capacity)
  let e = @execution.execution_capacity_execution_bytes(capacity)
  assert_eq(r, 786560L)
  assert_true(e > r && e < 512L * 1024L * 1024L)
  println("SDK-v4 additional demand retained=\{r} execution=\{e}")
}
