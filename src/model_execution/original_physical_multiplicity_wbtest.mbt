///|
// Synthetic byte grants isolate the existing multiplicity and lifetime laws.
// The factory counter is a Core fixture, not an actual SDK construction.
// These grants price neither schemas nor a normal installed Node layout.
fn original_physical_multiplicity_limits() -> ModelExecutionLimits {
  let base = prepared_capacity_test_limits(100L + 2L * 83920L)
  { ..base, ledger: { ..base.ledger, attempts: 1, }, }
}

///|
test "original physical multiplicity keeps all rows but constructs only eligible cursors" {
  for
    (mask, eligible) in [
      ([false, false], 0),
      ([true, false], 1),
      ([false, true], 1),
    ] {
    let rows = prepared_capacity_test_rows()
    let limits = original_physical_multiplicity_limits()
    let quantities : ModelQuantityCapacity = {
      limits: { tokens: 128L, cost_units: 0L, duration_ms: 2L, },
      per_attempt: { tokens: 64L, cost_units: 0L, duration_ms: 1L, },
    }
    let grant = original_startup_test_grant(
      rows,
      limits,
      Some(quantities.limits),
    )
    let starts = Ref(0)
    let sends = Ref(0)
    let released = Ref(false)
    let provider = install_model_provider("models/fixture", _ => {
      sends.val += 1
      Err(ProviderError)
    }).unwrap()
    let preflight : ModelPhysicalPreflight = _ => {
      starts.val += 1
      Ok({ advance: () => Ok(None), cleanup: () => released.val, })
    }
    let active = start_model_owned(
      rows,
      Provider(provider),
      "sha256:" + "a".repeat(64),
      limits,
      None,
      durable_calls=true,
      send_mask=Some(mask),
      quantity_capacity=Some(quantities),
      physical_preflight=Some(preflight),
      original_startup=Some(grant),
    ).unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      if eligible == 0 {
        if active.state.progress.phase is DispatchSlot {
          reached = true
          break
        }
      } else if starts.val == eligible {
        reached = true
        break
      }
      assert_true(advance_model_execution(active, 1).unwrap() is Continue(_, _))
    }
    assert_true(reached)
    assert_true(physical_equal(active.state.ledger, grant.ledger))
    assert_true(@resources.capacity_reservation_open(grant.capacity))
    // Both canonical original requests remain, including the masked NULL row.
    assert_eq(active.state.requests.length(), 2)
    assert_true(
      active.state.requests[0].request.key[0].value is @admitted.Text("a"),
    )
    assert_true(
      active.state.requests[1].request.key[0].value is @admitted.Text("b"),
    )
    assert_true(
      active.state.requests[1].request.inputs[0].1.value is @admitted.Null,
    )
    assert_eq(starts.val, eligible)
    assert_eq(active.state.physical_cursors.length(), eligible)
    assert_eq(@resources.ledger_usage(grant.ledger).reserved_attempts, eligible)
    assert_eq(@resources.ledger_usage(grant.ledger).attempts, 0)
    assert_eq(sends.val, 0)
    assert_true(request_model_cancel(active))
    assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
    if eligible > 0 {
      assert_false(cleanup_model_execution(active).unwrap())
      assert_true(@resources.capacity_reservation_open(grant.capacity))
      assert_false(@relation.cleanup_prepared_infer_rows(rows))
    }
    released.val = true
    assert_true(cleanup_model_execution(active).unwrap())
    assert_false(@resources.capacity_reservation_open(grant.capacity))
    assert_true(@relation.cleanup_prepared_infer_rows(rows))
    // No provider was dispatched. Cleanup releases reserved slots without
    // inventing attempted work or beginning another cursor.
    assert_eq(@resources.ledger_usage(grant.ledger).attempts, 0)
    assert_eq(@resources.ledger_usage(grant.ledger).reserved_attempts, 0)
    assert_eq(starts.val, eligible)
    assert_eq(sends.val, 0)
  }
}

///|
test "original physical multiplicity rejects two eligible rows before any physical factory" {
  let rows = prepared_capacity_test_rows()
  let limits = original_physical_multiplicity_limits()
  let quantities : ModelQuantityCapacity = {
    limits: { tokens: 128L, cost_units: 0L, duration_ms: 2L, },
    per_attempt: { tokens: 64L, cost_units: 0L, duration_ms: 1L, },
  }
  let grant = original_startup_test_grant(rows, limits, Some(quantities.limits))
  let starts = Ref(0)
  let sends = Ref(0)
  let provider = install_model_provider("models/fixture", _ => {
    sends.val += 1
    Err(ProviderError)
  }).unwrap()
  let preflight : ModelPhysicalPreflight = _ => {
    starts.val += 1
    Ok({ advance: () => Ok(None), cleanup: () => true, })
  }
  let active = start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    durable_calls=true,
    send_mask=Some([true, true]),
    quantity_capacity=Some(quantities),
    physical_preflight=Some(preflight),
    original_startup=Some(grant),
  ).unwrap()
  let mut refused = false
  for _ in 0..<1000 {
    match advance_model_execution(active, 1).unwrap() {
      Continue(_, _) => continue
      Failed(Ledger(@resources.AttemptLimit), _, _) => {
        refused = true
        break
      }
      _ =>
        abort("Expected the original attempt limit before physical preparation")
    }
  }
  assert_true(refused)
  assert_true(physical_equal(active.state.ledger, grant.ledger))
  assert_eq(@resources.ledger_usage(grant.ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(grant.ledger).reserved_attempts, 1)
  assert_eq(active.state.requests.length(), 0)
  assert_eq(active.state.physical_cursors.length(), 0)
  assert_eq(starts.val, 0)
  assert_eq(sends.val, 0)
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_true(cleanup_model_execution(active).unwrap())
  assert_false(@resources.capacity_reservation_open(grant.capacity))
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
  assert_eq(@resources.ledger_usage(grant.ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(grant.ledger).reserved_attempts, 0)
  assert_eq(starts.val, 0)
  assert_eq(sends.val, 0)
}
