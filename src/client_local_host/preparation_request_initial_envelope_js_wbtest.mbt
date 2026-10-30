///|
test "Request initial owner accepts its actual composed original envelope without another current" {
  let input = [1]
  let policy = client_local_resource_policy()
  let ordinary = client_local_preparation_initial_limits(policy).unwrap()
  let composed = @resources.add_ledger_limits(
    ordinary, effect_model_plan_limits,
  ).unwrap()
  let calls = Ref(0)
  let initial = request_parent_fixture(
    input,
    current=() => {
      calls.val += 1
      true
    },
    initial_limits=Some(composed),
  )
  let parent = match begin_request_preparation(initial, input, policy) {
    Ok(value) => value
    Err(Policy) =>
      fail("actual original composed envelope rejected as ordinary-only Policy")
    Err(_) => fail("other original Request refusal")
  }
  assert_true(physical_equal(parent.initial, initial))
  assert_eq(@resources.ledger_limits(parent.ledger), composed)
  assert_eq(
    @resources.node_local_preparation_limits(initial, input),
    Ok(composed),
  )
  // Compare the same actual opening boundary, including its existing Node
  // supplier callbacks. A guessed fixed callback count is not evidence.
  let ordinary_calls = Ref(0)
  let ordinary_input = [0]
  let ordinary_initial = request_parent_fixture(ordinary_input, current=() => {
    ordinary_calls.val += 1
    true
  })
  let baseline = begin_request_preparation(
    ordinary_initial, ordinary_input, policy,
  ).unwrap()
  assert_eq(calls.val, ordinary_calls.val)
  abort_request_preparation_after_cleanup(baseline).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 1)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request initial envelope retains all six ordinary baseline one-short refusals" {
  let policy = client_local_resource_policy()
  let base = client_local_preparation_initial_limits(policy).unwrap()
  for index in 0..<6 {
    let short = match index {
      0 => { ..base, planning_work: base.planning_work - 1, }
      1 => { ..base, attempts: base.attempts - 1, }
      2 => { ..base, holdings: base.holdings - 1, }
      3 => { ..base, transfer_bytes: base.transfer_bytes - 1L, }
      4 => { ..base, retained_bytes: base.retained_bytes - 1L, }
      _ => { ..base, execution_bytes: base.execution_bytes - 1L, }
    }
    let input = [index]
    let initial = request_parent_fixture(input, initial_limits=Some(short))
    assert_true(
      begin_request_preparation(initial, input, policy) is Err(Policy),
    )
    assert_eq(
      @resources.node_local_preparation_limits(initial, input),
      Ok(short),
    )
    @resources.cleanup_node_preparation_admission(initial).unwrap()
  }
}
