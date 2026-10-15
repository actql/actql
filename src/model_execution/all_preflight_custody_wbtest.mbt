///|
test "original Model holds all eligible preflight plans until every cleanup succeeds" {
  // Synthetic 100/5 tests SAME original Ledger lifetime, not a physical Node
  // upper bound. The real Owner prepares all M plans before any dispatch;
  // no active transport/Slot limit is substituted for this prepared count.
  for
    (mask, eligible) in [
      ([true, true], 2),
      ([true, false], 1),
      ([false, false], 0),
    ] {
    let rows = prepared_capacity_test_rows()
    let limits = prepared_capacity_test_limits(
      100L + eligible.to_int64() * 83920L,
    )
    let quantity : ModelQuantityCapacity = {
      limits: { tokens: 64L, cost_units: 0L, duration_ms: 2L, },
      per_attempt: { tokens: 32L, cost_units: 0L, duration_ms: 1L, },
    }
    let grant = original_startup_test_grant(rows, limits, Some(quantity.limits))
    let sends = Ref(0)
    let starts = Ref(0)
    let advances = [0, 0]
    let cleanups = [0, 0]
    let released = [false, false]
    let provider = install_model_provider("models/fixture", _ => {
      sends.val += 1
      Err(ProviderError)
    }).unwrap()
    let preflight : ModelPhysicalPreflight = request => {
      starts.val += 1
      let slot = request.slot
      let plan = match
        model_physical_request_plan(request, 1L, quantity.per_attempt, () => {
          sends.val += 1
          Err(ProviderError)
        }) {
        Ok(plan) => plan
        Err(issue) => return Err(issue)
      }
      Ok({
        advance: () => {
          advances[slot] += 1
          Ok(Some(plan))
        },
        cleanup: () => {
          cleanups[slot] += 1
          released[slot]
        },
      })
    }
    let active = start_model_owned(
      rows,
      Provider(provider),
      "sha256:" + "a".repeat(64),
      limits,
      None,
      durable_calls=true,
      send_mask=Some(mask),
      quantity_capacity=Some(quantity),
      physical_preflight=Some(preflight),
      original_startup=Some(grant),
    ).unwrap()
    assert_true(physical_equal(active.state.ledger, grant.ledger))
    for _ in 0..<1000 {
      if active.state.progress.phase is DispatchSlot {
        break
      }
      assert_true(advance_model_execution(active, 1).unwrap() is Continue(_, _))
      assert_true(@resources.capacity_reservation_open(grant.capacity))
    }
    assert_true(active.state.progress.phase is DispatchSlot)
    assert_eq(active.state.requests.length(), 2)
    assert_eq(starts.val, eligible)
    assert_eq(active.state.physical_cursors.length(), eligible)
    assert_eq(active.state.physical_plans.length(), eligible)
    assert_eq(advances, [
      if eligible > 0 {
        1
      } else {
        0
      },
      if eligible == 2 {
        1
      } else {
        0
      },
    ])
    assert_eq(sends.val, 0)
    assert_eq(
      model_execution_quantity_usage(active).reserved.tokens,
      eligible.to_int64() * 32L,
    )
    let before = model_execution_resource_usage(active)
    let quantities = model_execution_quantity_usage(active)
    assert_eq(
      before.reserved_retention_bytes,
      100L + eligible.to_int64() * 83920L,
    )
    assert_eq(before.reserved_execution_bytes, 5L + eligible.to_int64() * 256L)
    assert_true(request_model_cancel(active))
    assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
    active.state.output_uses = 1
    assert_false(cleanup_model_execution(active).unwrap())
    assert_eq(cleanups, [0, 0])
    assert_true(@resources.capacity_reservation_open(grant.capacity))
    active.state.output_uses = 0
    if eligible > 0 {
      assert_false(cleanup_model_execution(active).unwrap())
      assert_eq(cleanups, [1, 0])
      assert_eq(active.state.physical_cleanup_index, 0)
      assert_eq(active.state.physical_plans.length(), eligible)
      assert_eq(model_execution_resource_usage(active), before)
      assert_eq(model_execution_quantity_usage(active), quantities)
      assert_false(@relation.cleanup_prepared_infer_rows(rows))
      released[0] = true
      if eligible == 2 {
        // First cursor has physically acknowledged, but the second and all
        // retained plans/requests STILL hold the original capacity/quantities.
        assert_false(cleanup_model_execution(active).unwrap())
        assert_eq(active.state.physical_cleanup_index, 1)
        assert_eq(cleanups, [2, 0])
        assert_false(cleanup_model_execution(active).unwrap())
        assert_eq(cleanups, [2, 1])
        assert_eq(active.state.physical_plans.length(), 2)
        assert_eq(active.state.physical_cursors.length(), 2)
        assert_eq(model_execution_resource_usage(active), before)
        assert_eq(model_execution_quantity_usage(active), quantities)
        assert_true(@resources.capacity_reservation_open(grant.capacity))
        released[1] = true
      }
    }
    assert_true(cleanup_model_execution(active).unwrap())
    assert_true(active.state.reclaimed)
    assert_eq(active.state.requests.length(), 0)
    assert_eq(active.state.requests.capacity(), 0)
    assert_eq(active.state.physical_cursors.length(), 0)
    assert_eq(active.state.physical_cursors.capacity(), 0)
    assert_eq(active.state.physical_plans.length(), 0)
    assert_false(@resources.capacity_reservation_open(grant.capacity))
    assert_eq(
      model_execution_resource_usage(active).reserved_retention_bytes,
      0L,
    )
    assert_eq(
      model_execution_resource_usage(active).reserved_execution_bytes,
      0L,
    )
    assert_eq(model_execution_quantity_usage(active).reserved.tokens, 0L)
    assert_true(@relation.cleanup_prepared_infer_rows(rows))
    let completed = cleanups.copy()
    assert_true(cleanup_model_execution(active).unwrap())
    assert_eq(cleanups, completed)
    assert_eq(sends.val, 0)
  }
}
