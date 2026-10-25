///|
test "current preflight refusal retains the original acquired child cleanup" {
  let advances = Ref(0)
  let cleanups = Ref(0)
  let live = Ref(false)
  let released = Ref(false)
  let original : ModelRequestPreflight = {
    advance: () => {
      advances.val += 1
      Ok(None)
    },
    cleanup: () => {
      cleanups.val += 1
      released.val
    },
  }
  let guarded = guard_model_request_preflight_current(original, () => live.val)
  assert_true((guarded.advance)() is Err(Cancelled))
  assert_eq(advances.val, 0)
  assert_false((guarded.cleanup)())
  assert_eq(cleanups.val, 1)
  released.val = true
  assert_true((guarded.cleanup)())
  assert_eq(cleanups.val, 2)
  assert_eq(advances.val, 0)
}

///|
test "current preflight delegates the same bounded result without changing work" {
  let advances = Ref(0)
  let live = Ref(true)
  let original : ModelRequestPreflight = {
    advance: () => {
      advances.val += 1
      Ok(None)
    },
    cleanup: () => true,
  }
  let guarded = guard_model_request_preflight_current(original, () => live.val)
  assert_true((guarded.advance)() is Ok(None))
  assert_eq(advances.val, 1)
  live.val = false
  assert_true((guarded.advance)() is Err(Cancelled))
  assert_eq(advances.val, 1)
  assert_true((guarded.cleanup)())
}

///|
test "factory current loss reaches original Model custody before refusal and retry cleanup" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L + 83920L)
  let quantity : ModelQuantityCapacity = {
    limits: { tokens: 64L, cost_units: 0L, duration_ms: 2L, },
    per_attempt: { tokens: 32L, cost_units: 0L, duration_ms: 1L, },
  }
  let grant = original_startup_test_grant(rows, limits, Some(quantity.limits))
  let current = Ref(true)
  let released = Ref(false)
  let starts = Ref(0)
  let advances = Ref(0)
  let cleanups = Ref(0)
  let sends = Ref(0)
  let provider = install_model_provider("models/fixture", _ => {
    sends.val += 1
    Err(ProviderError)
  }).unwrap()
  let preflight : ModelPhysicalPreflight = _ => {
    starts.val += 1
    let acquired : ModelRequestPreflight = {
      advance: () => {
        advances.val += 1
        Ok(None)
      },
      cleanup: () => {
        cleanups.val += 1
        released.val
      },
    }
    current.val = false
    // No post-factory throw. This same child reaches the Model's inventory.
    Ok(guard_model_request_preflight_current(acquired, () => current.val))
  }
  let active = start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    durable_calls=true,
    send_mask=Some([true, false]),
    quantity_capacity=Some(quantity),
    physical_preflight=Some(preflight),
    original_startup=Some(grant),
  ).unwrap()
  for _ in 0..<1000 {
    let poll = advance_model_execution(active, 1).unwrap()
    if poll is Continue(_, _) {
      continue
    }
    assert_true(poll is Failed(Cancelled, _, _))
    break
  }
  assert_eq(starts.val, 1)
  assert_eq(advances.val, 0)
  assert_eq(active.state.physical_cursors.length(), 1)
  assert_eq(sends.val, 0)
  assert_false(cleanup_model_execution(active).unwrap())
  assert_eq(cleanups.val, 1)
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_false(@relation.cleanup_prepared_infer_rows(rows))
  released.val = true
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(cleanups.val, 2)
  assert_false(@resources.capacity_reservation_open(grant.capacity))
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
  assert_eq(sends.val, 0)
}
