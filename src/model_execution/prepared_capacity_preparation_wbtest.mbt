///|
test "Model prepared capacity: every masked row remains prepared before dispatch" {
  // The fixed 100/5 envelope tests the connection, not a physical Model formula.
  // Eligibility is deliberately varied without changing the prepared inventory.
  // One eligible attempt retains 1000 request + 1000 response + the existing
  // occupied 81920 evidence allowance. It is separate from the byte-only claim.
  let attempt_bytes = 83920L
  for (mask, eligible) in [([false, false], 0), ([true, false], 1)] {
    let rows = prepared_capacity_test_rows()
    let sends = Ref(0)
    let provider = install_model_provider("models/fixture", _ => {
      sends.val += 1
      Err(ProviderError)
    }).unwrap()
    let active = start_model_owned(
      rows,
      Provider(provider),
      "sha256:" + "a".repeat(64),
      prepared_capacity_test_limits(100L + eligible.to_int64() * attempt_bytes),
      None,
      durable_calls=true,
      send_mask=Some(mask),
      prepared_capacity=Some((2, 100L, 5L)),
    ).unwrap()
    let claim = active.state.prepared_capacity.unwrap()
    let mut ready = false
    for _ in 0..<1000 {
      if active.state.progress.phase is DispatchSlot {
        ready = true
        break
      }
      assert_true(advance_model_execution(active, 1).unwrap() is Continue(_, _))
      assert_true(@resources.capacity_reservation_open(claim))
      assert_eq(
        model_execution_resource_usage(active).reserved_retention_bytes,
        100L + active.state.reservations.length().to_int64() * attempt_bytes,
      )
    }
    assert_true(ready)
    assert_eq(active.state.requests.length(), 2)
    // PreparedInferRows' existing canonical typed-key order is a then b, not
    // the source order b then a. Fix both values independently of eligibility;
    // preparation cannot discard the masked NULL row or change its identity.
    assert_true(
      active.state.requests[0].request.key[0].value is @admitted.Text("a"),
    )
    assert_true(
      active.state.requests[0].request.inputs[0].1.value
      is @admitted.Text("urgent"),
    )
    assert_true(
      active.state.requests[1].request.key[0].value is @admitted.Text("b"),
    )
    assert_true(
      active.state.requests[1].request.inputs[0].1.value is @admitted.Null,
    )
    assert_eq(sends.val, 0)
    // Preparation reserves eligible slots but has not dispatched an attempt.
    assert_eq(@resources.ledger_usage(active.state.ledger).attempts, 0)
    assert_eq(
      @resources.ledger_usage(active.state.ledger).reserved_attempts,
      eligible,
    )
    assert_eq(
      model_execution_resource_usage(active).reserved_retention_bytes,
      100L + eligible.to_int64() * attempt_bytes,
    )
    assert_false(@relation.cleanup_prepared_infer_rows(rows))
    assert_true(request_model_cancel(active))
    assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
    assert_true(cleanup_model_execution(active).unwrap())
    assert_false(@resources.capacity_reservation_open(claim))
    assert_eq(active.state.requests.length(), 0)
    assert_eq(active.state.requests.capacity(), 0)
    assert_true(@relation.cleanup_prepared_infer_rows(rows))
    assert_eq(sends.val, 0)
    assert_eq(@resources.ledger_usage(active.state.ledger).attempts, 0)
    assert_eq(@resources.ledger_usage(active.state.ledger).reserved_attempts, 0)
  }
}
