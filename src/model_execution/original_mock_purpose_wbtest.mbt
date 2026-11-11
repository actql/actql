///|
// Pure refusal arithmetic within the existing Model owner. These scalar
// counts issue no original startup, physical Ledger, grant or restore proof.
test "shared Mock cap counts authenticated saved and Unknown attempts as spent" {
  let bound : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 4000L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  assert_true(
    check_original_mock_attempt_budget(bound, 1, 1, 1, 1000L) is Ok(_),
  )
  assert_true(
    check_original_mock_attempt_budget(
      { ..bound, attempts: 3, },
      1,
      1,
      1,
      1000L,
    )
    is Err(Ledger(@resources.AttemptLimit)),
  )
  assert_true(
    check_original_mock_attempt_budget(
      { ..bound, transfer_bytes: 3999L, },
      1,
      1,
      1,
      1000L,
    )
    is Err(Ledger(@resources.TransferLimit)),
  )
  // Even one slot can retain both an entered Unknown and a reconciliation
  // read reservation. Closing another token cannot erase either history.
  assert_true(
    check_original_mock_attempt_budget(
      { ..bound, attempts: 2, },
      1,
      0,
      1,
      1000L,
    )
    is Err(Ledger(@resources.AttemptLimit)),
  )
  assert_true(
    check_original_mock_attempt_budget(bound, 2147483647, 2147483647, 0, 0L)
    is Err(Ledger(@resources.AttemptLimit)),
  )
}

///|
// Synthetic original startup/trace ports isolate component accounting. They
// are not an SDK grant, authenticated saved call or normal physical recipe.
fn shared_quantity_test_execution(
  capacity : ModelQuantityCapacity,
  retained? : Int64 = 100L,
) -> ModelExecution raise {
  let rows = prepared_capacity_test_rows()
  let base = prepared_capacity_test_limits(retained)
  let limits = {
    ..base,
    ledger: { ..base.ledger, attempts: 10, transfer_bytes: 20000L, },
  }
  let original = original_startup_test_grant(
    rows,
    limits,
    Some({ tokens: 1320L, cost_units: 20L, duration_ms: 20000L, }),
  )
  let provider = install_model_provider("models/fixture", _ => {
    abort("quantity control never invokes a provider")
  }).unwrap()
  let startup = {
    ..original,
    shared_mock: Some({
      provider,
      limits,
      publication_retained: 0L,
      publication_execution: 0L,
      publication_planning: 0,
    }),
  }
  start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    durable_calls=true,
    send_mask=Some([false, false]),
    quantity_capacity=Some(capacity),
    original_startup=Some(startup),
  ).unwrap()
}

///|
fn shared_quantity_test_observed_attempt(
  active : ModelExecution,
  slot : Int,
  tokens : Int64,
) -> Unit {
  let state = active.state
  let reservation = @resources.reserve_attempt(
    state.ledger,
    0L,
    0L,
    0L,
    quantities=Some(state.quantity_capacity.unwrap().per_attempt),
  ).unwrap()
  state.reservations[slot] = reservation
  @resources.mark_quantities_uncertain(state.ledger, reservation).unwrap()
  @resources.observe_quantities(state.ledger, reservation, tokens=Some(tokens)).unwrap()
  let (authority, _, _, _) = restored_attachment_test_originals()
  state.attempts[slot] = {
    attempt: authority,
    call: authority,
    authority,
    reservation: Some(state.quantity_capacity.unwrap().per_attempt),
    input_tokens: Some(tokens),
    output_tokens: Some(0L),
    category: "ok",
    failure: None,
    work: 0,
    response_cid: None,
    output_cid: None,
    response_issuer: None,
    evidence: None,
  }
  @resources.settle_reservation(state.ledger, reservation).unwrap()
}

///|
test "shared Model quantities preserve dedicated observed-use admission and retain Unknown without refund" {
  let capacity : ModelQuantityCapacity = {
    limits: { tokens: 66L, cost_units: 0L, duration_ms: 2000L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
  let active = shared_quantity_test_execution(capacity)
  let dedicated = @resources.create_ledger(active.state.limits.ledger).unwrap()
  @resources.configure_quantities(dedicated, capacity.limits).unwrap()
  for slot in 0..<2 {
    assert_true(
      check_original_mock_capacity(
        active.state,
        0L,
        0L,
        reserve_quantities=true,
      )
      is Ok(_),
    )
    shared_quantity_test_observed_attempt(active, slot, 3L)
    let attempt = @resources.reserve_attempt(
      dedicated,
      0L,
      0L,
      0L,
      quantities=Some(capacity.per_attempt),
    ).unwrap()
    @resources.mark_quantities_uncertain(dedicated, attempt).unwrap()
    @resources.observe_quantities(dedicated, attempt, tokens=Some(3L)).unwrap()
    @resources.settle_reservation(dedicated, attempt).unwrap()
  }
  let before = @resources.quantity_usage(active.state.ledger)
  assert_eq(before, @resources.quantity_usage(dedicated))
  assert_eq(before.consumed.tokens, 6L)
  assert_eq(before.uncertain.duration_ms, 1000L)
  // A third envelope fits after two actual three-token observations. Counting
  // three worst-case envelopes would incorrectly reject this original case.
  assert_true(
    check_original_mock_capacity(active.state, 0L, 0L, reserve_quantities=true)
    is Ok(_),
  )
  assert_eq(@resources.quantity_usage(active.state.ledger), before)
  let third = @resources.reserve_attempt(
    active.state.ledger,
    0L,
    0L,
    0L,
    quantities=Some(capacity.per_attempt),
  ).unwrap()
  active.state.reservations[2] = third
  let original_third = @resources.reserve_attempt(
    dedicated,
    0L,
    0L,
    0L,
    quantities=Some(capacity.per_attempt),
  ).unwrap()
  assert_true(
    check_original_mock_capacity(active.state, 0L, 0L, reserve_quantities=true)
    is Err(Ledger(@resources.TokenLimit)),
  )
  assert_true(
    @resources.reserve_attempt(
      dedicated,
      0L,
      0L,
      0L,
      quantities=Some(capacity.per_attempt),
    )
    is Err(@resources.TokenLimit),
  )
  // Unknown consumption stays charged even after physical reservation close.
  @resources.mark_quantities_uncertain(active.state.ledger, third).unwrap()
  @resources.settle_reservation(active.state.ledger, third).unwrap()
  assert_true(
    check_original_mock_capacity(active.state, 0L, 0L, reserve_quantities=true)
    is Err(Ledger(@resources.TokenLimit)),
  )
  @resources.settle_reservation(dedicated, original_third).unwrap()
  assert_true(request_model_cancel(active))
  advance_model_execution(active, 1).unwrap() |> ignore
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(@resources.quantity_usage(active.state.ledger).consumed.tokens, 6L)
  assert_eq(
    @resources.quantity_usage(active.state.ledger).uncertain.tokens,
    33L,
  )
}

///|
test "shared Model component ceilings refuse below the parent for reserved and Unknown original slots" {
  for
    (tokens, cost_units, duration_ms, issue) in [
      (65L, 2L, 1000L, @resources.TokenLimit),
      (66L, 1L, 1000L, @resources.CostLimit),
      (66L, 2L, 999L, @resources.DurationLimit),
    ] {
    for unknown in [false, true] {
      let capacity : ModelQuantityCapacity = {
        limits: { tokens, cost_units, duration_ms, },
        per_attempt: { tokens: 33L, cost_units: 1L, duration_ms: 500L, },
      }
      let active = shared_quantity_test_execution(capacity)
      assert_true(
        check_original_mock_capacity(
          active.state,
          0L,
          0L,
          reserve_quantities=true,
        )
        is Ok(_),
      )
      let attempt = @resources.reserve_attempt(
        active.state.ledger,
        0L,
        0L,
        0L,
        quantities=Some(capacity.per_attempt),
      ).unwrap()
      active.state.reservations[0] = attempt
      if unknown {
        @resources.mark_quantities_uncertain(active.state.ledger, attempt).unwrap()
        @resources.settle_reservation(active.state.ledger, attempt).unwrap()
      }
      let before = @resources.quantity_usage(active.state.ledger)
      assert_true(
        check_original_mock_capacity(
          active.state,
          0L,
          0L,
          reserve_quantities=true,
        )
        is Err(Ledger(actual)) &&
        actual == issue,
      )
      assert_eq(@resources.quantity_usage(active.state.ledger), before)
      // The aggregate has room; refusal really came from this component.
      let parent = @resources.reserve_attempt(
        active.state.ledger,
        0L,
        0L,
        0L,
        quantities=Some(capacity.per_attempt),
      ).unwrap()
      @resources.settle_reservation(active.state.ledger, parent).unwrap()
      assert_true(request_model_cancel(active))
      advance_model_execution(active, 1).unwrap() |> ignore
      assert_true(cleanup_model_execution(active).unwrap())
    }
  }
}

///|
// Actual Resource tokens on the same original Model's ledger isolate the
// read-versus-dispatch dimension. Historical evidence is an explicit fixture;
// this does not issue a Model reconciliation token or qualify public recovery.
test "original response lookup retains Unknown without another invocation budget" {
  let quantities : ModelQuantityCapacity = {
    limits: { tokens: 66L, cost_units: 0L, duration_ms: 1000L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
  let active = shared_quantity_test_execution(
    quantities,
    retained=100L + 2L * 83920L,
  )
  let state = active.state
  let original = state.original_startup.unwrap()
  let purpose = original.shared_mock.unwrap()
  let limits = {
    ..purpose.limits,
    ledger: { ..purpose.limits.ledger, attempts: 2, },
  }
  state.original_startup = Some({
    ..original,
    shared_mock: Some({ ..purpose, limits, }),
  })
  let unsent = @resources.reserve_attempt(
    state.ledger,
    2000L,
    83920L,
    0L,
    quantities=Some(quantities.per_attempt),
  ).unwrap()
  state.reservations[1] = unsent
  let (authority, _, _, _) = restored_attachment_test_originals()
  state.unknown_calls[0] = { attempt: authority, authority, }
  let before = @resources.ledger_usage(state.ledger)
  // Another INVOCATION is still refused: the original Unknown and the
  // unsent slot already occupy this selected two-attempt Model contract.
  assert_true(
    check_original_mock_attempt_capacity(state, 2000L, 83920L, 0L)
    is Err(Ledger(@resources.AttemptLimit)),
  )
  check_original_mock_capacity(state, 83920L, 0L, reserve_quantities=true).unwrap()
  assert_eq(@resources.ledger_usage(state.ledger), before)
  // The separate same-Run lookup custody still charges actual finite bytes
  // and Unknown quantities. It neither refunds that history nor permits send.
  let lookup = @resources.reserve_attempt(
    state.ledger,
    2000L,
    83920L,
    0L,
    quantities=Some(quantities.per_attempt),
  ).unwrap()
  state.reservations[0] = lookup
  @resources.consume_reserved_attempt(state.ledger, lookup).unwrap()
  @resources.mark_quantities_uncertain(state.ledger, lookup).unwrap()
  assert_eq(@resources.ledger_usage(state.ledger).attempts, 1)
  assert_eq(
    @resources.ledger_usage(state.ledger).reserved_retention_bytes,
    before.reserved_retention_bytes + 83920L,
  )
  assert_true(state.unknown_calls.contains(0))
  assert_true(
    state.reservations.get(1) is Some(same) && physical_equal(same, unsent),
  )
  let (_, uncertain, _) = @resources.reservation_quantity_state(
    state.ledger,
    lookup,
  ).unwrap()
  assert_eq(uncertain, Some(quantities.per_attempt))
  assert_true(
    check_original_mock_attempt_capacity(state, 2000L, 83920L, 0L)
    is Err(Ledger(@resources.AttemptLimit)),
  )
  request_model_cancel(active) |> ignore
  advance_model_execution(active, 1).unwrap() |> ignore
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(@resources.ledger_usage(state.ledger).attempts, 1)
  // Cleanup retires physical custody without erasing historical Unknown.
  assert_true(state.unknown_calls.contains(0))
  assert_eq(
    @resources.reservation_quantity_state(state.ledger, lookup).unwrap().1,
    Some(quantities.per_attempt),
  )
}
