///|
fn fixture_quantity_capacity(
  tokens : Int64,
  duration : Int64,
) -> @model.ModelQuantityCapacity {
  {
    limits: { tokens, cost_units: 0L, duration_ms: duration, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
}

///|
test "selected Infer reserves all token and duration envelopes before dispatch" {
  for
    (tokens, duration, expected) in [
      (66L, 1000L, None),
      (65L, 1000L, Some(@resources.TokenLimit)),
      (66L, 999L, Some(@resources.DurationLimit)),
    ] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, 2, 133072L)
    bind_quantity_capacity(active, fixture_quantity_capacity(tokens, duration)).unwrap()
    match expected {
      Some(issue) => {
        assert_true(
          fixture_finish(active) is Failed(Model(@model.Ledger(actual)), ..) &&
          actual == issue,
        )
        assert_eq(calls.val, 0)
        assert_true(acquire_output(active) is None)
        let before = execution_quantity_usage(active).unwrap()
        assert_eq(before.reserved.tokens, 33L)
        assert_eq(before.reserved.duration_ms, 500L)
        assert_eq(before.consumed.tokens, 0L)
        assert_eq(before.uncertain.tokens, 0L)
      }
      None => {
        assert_true(fixture_finish(active) is Complete(_, ..))
        assert_eq(calls.val, 2)
        let before = execution_quantity_usage(active).unwrap()
        assert_eq(before.reserved.tokens, 0L)
        assert_eq(before.consumed.tokens, 6L)
        assert_eq(before.uncertain.tokens, 0L)
        assert_eq(before.uncertain.duration_ms, 1000L)
      }
    }
    assert_true(cleanup(active).unwrap())
    let after = execution_quantity_usage(active).unwrap()
    assert_eq(after.reserved.tokens, 0L)
    assert_eq(after.reserved.duration_ms, 0L)
    assert_eq(after.consumed.tokens, if expected is None { 6L } else { 0L })
    assert_eq(
      after.uncertain.duration_ms,
      if expected is None {
        1000L
      } else {
        0L
      },
    )
  }
}

///|
test "the Contract cannot widen or be widened by installed quantity capacity" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  bind_quantity_capacity(active, {
    ..fixture_quantity_capacity(10000L, 10000L),
    per_attempt: { tokens: 65L, cost_units: 0L, duration_ms: 500L, },
  }).unwrap()
  assert_true(
    bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L))
    is Err(InvalidAdvance),
  )
  assert_true(
    fixture_finish(active)
    is Failed(Model(@model.Ledger(@resources.TokenLimit)), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  bind_quantity_capacity(active, {
    limits: { tokens: 66L, cost_units: 1000L, duration_ms: 1000L, },
    per_attempt: { tokens: 33L, cost_units: 1L, duration_ms: 500L, },
  }).unwrap()
  assert_true(
    fixture_finish(active)
    is Failed(Model(@model.Ledger(@resources.CostLimit)), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
}

///|
test "Infer cancellation keeps observed usage and undispatched cleanup responsibility" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L)
  bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
  let mut progressed = false
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    assert_true(poll is Continue(_))
    if calls.val == 1 {
      progressed = true
      break
    }
  }
  assert_true(progressed)
  let before = execution_quantity_usage(active).unwrap()
  assert_eq(before.consumed.tokens, 3L)
  assert_eq(before.uncertain.duration_ms, 500L)
  assert_eq(before.reserved.tokens, 33L)
  assert_eq(before.reserved.duration_ms, 500L)
  assert_true(cancel(active))
  assert_true(advance(active, 1).unwrap() is Stopped(_))
  assert_true(acquire_output(active) is None)
  assert_true(cleanup(active).unwrap())
  let after = execution_quantity_usage(active).unwrap()
  assert_eq(after.consumed.tokens, 3L)
  assert_eq(after.uncertain.duration_ms, 500L)
  assert_eq(after.reserved.tokens, 0L)
  assert_eq(after.reserved.duration_ms, 0L)
  assert_eq(calls.val, 1)
}

///|
test "no-response Infer failure keeps unknown quantity envelopes after cleanup" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  bind_quantity_capacity(active, fixture_quantity_capacity(33L, 500L)).unwrap()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
  let before = execution_quantity_usage(active).unwrap()
  assert_eq(before.consumed.tokens, 0L)
  assert_eq(before.uncertain.tokens, 33L)
  assert_eq(before.uncertain.duration_ms, 500L)
  assert_true(cleanup(active).unwrap())
  assert_eq(execution_quantity_usage(active).unwrap(), before)
}
