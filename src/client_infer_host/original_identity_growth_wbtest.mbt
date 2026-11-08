///|
// Actual checked Model, its original output and the real Resource byte token.
// Provider/current/allowances are fixture ports, not installed physical IO.
fn original_identity_growth_scan(
  output : @relation.CompletedOutput,
  broad : Bool,
) -> @relation.CompletedRelationIdentityScan {
  let wire : @relation.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: if broad {
      16777216
    } else {
      10000
    },
    max_nodes: if broad {
      1048576
    } else {
      1000
    },
    max_depth: if broad {
      1024
    } else {
      20
    },
  }
  @relation.start_completed_relation_identity_scan(
    output,
    10,
    standard_limits().output_values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    100000,
    if broad {
      4000000
    } else {
      10000
    },
    incremental_metadata=true,
  ).unwrap()
}

///|
test "same original publication backs actual identity steps without output-max startup" {
  let calls = Ref(0)
  let (active, ledger, _) = original_observation_test_start(
    provider=original_funded_start_provider(calls),
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
  let held = acquire_output(active).unwrap()
  let bound = active.run_binding.unwrap()
  let (_, output) = borrow_original_live_model_relations(
    held,
    bound.compiled,
    bound.definition,
    active.plan.unwrap(),
  ).unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let start = @relation.completed_relation_identity_scan_start_construction_capacity(
    output,
  ).unwrap()
  grow_original_infer_publication_capacity(
    active,
    capacity,
    @relation.execution_capacity_retained_bytes(start),
    @relation.execution_capacity_execution_bytes(start),
  ).unwrap()
  let small = original_identity_growth_scan(output, false)
  let previous = @relation.completed_relation_identity_scan_next_construction_capacity(
    small,
  ).unwrap()
  assert_true(@relation.cancel_completed_relation_identity_scan(small))
  let scan = original_identity_growth_scan(output, true)
  let initial = @relation.completed_relation_identity_scan_next_construction_capacity(
    scan,
  ).unwrap()
  assert_eq(
    @relation.execution_capacity_retained_bytes(initial),
    @relation.execution_capacity_retained_bytes(previous),
  )
  let initial_usage = @resources.ledger_usage(ledger)
  let mut peak = 0L
  let mut done = false
  while !done {
    let quote = @relation.completed_relation_identity_scan_next_construction_capacity(
      scan,
    ).unwrap()
    let retained = @relation.execution_capacity_retained_bytes(quote)
    let execution = @relation.execution_capacity_execution_bytes(quote)
    grow_original_infer_publication_capacity(
      active, capacity, retained, execution,
    ).unwrap()
    peak = Int64::max(peak, retained)
    done = @relation.advance_completed_relation_identity_scan(scan, 1).unwrap().0
  }
  // Independent regression ceiling for this tiny authored output, not a new
  // production quota or a measurement of heap/RSS. Old max-file quotes exceed it.
  assert_true(peak < 1048576L)
  let receipt = @relation.finish_completed_relation_identity_scan(scan).unwrap()
  assert_true(
    @relation.completed_relation_export_matches_output(receipt, output),
  )
  let final_usage = @resources.ledger_usage(ledger)
  assert_eq(final_usage.live_reservations, initial_usage.live_reservations)
  assert_eq(final_usage.attempts, initial_usage.attempts)
  assert_eq(calls.val, 1)
  @relation.cancel_completed_relation_export_receipt(receipt)
  assert_true(release_output(held))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "identity backing refusal precedes next construction and preserves same retry token" {
  // Select the extra fixture census slot before its original read descriptor
  // is issued. Never resize a producer frozen in that original descriptor.
  let (active, ledger, _) = original_observation_test_start(
    spare_publication_slot=true,
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  let held = acquire_output(active).unwrap()
  let bound = active.run_binding.unwrap()
  let (_, output) = borrow_original_live_model_relations(
    held,
    bound.compiled,
    bound.definition,
    active.plan.unwrap(),
  ).unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let start = @relation.completed_relation_identity_scan_start_construction_capacity(
    output,
  ).unwrap()
  grow_original_infer_publication_capacity(
    active,
    capacity,
    @relation.execution_capacity_retained_bytes(start),
    @relation.execution_capacity_execution_bytes(start),
  ).unwrap()
  let scan = original_identity_growth_scan(output, true)
  let usage = @resources.ledger_usage(ledger)
  let limits = @resources.ledger_limits(ledger)
  let blocker = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    1L,
    0L,
  ).unwrap()
  let quote = @relation.completed_relation_identity_scan_next_construction_capacity(
    scan,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  match
    grow_original_infer_publication_capacity(
      active,
      capacity,
      @relation.execution_capacity_retained_bytes(quote),
      @relation.execution_capacity_execution_bytes(quote),
    ) {
    Err(Model(@model.Ledger(issue))) =>
      assert_eq(issue, @resources.RetentionLimit)
    Err(Model(@model.OutputIdentity)) =>
      abort("headroom: original identity refused")
    Err(_) => abort("headroom: non-Ledger refusal")
    Ok(_) => abort("headroom: growth unexpectedly succeeded")
  }
  assert_eq(@relation.completed_relation_identity_scan_work(scan), 0L)
  assert_eq(@resources.ledger_usage(ledger), before)
  // This fixture reservation was never dispatched and owns no physical IO.
  // Its original settlement returns reserved bytes, not consumed attempts.
  @resources.settle_capacity(ledger, blocker).unwrap()
  grow_original_infer_publication_capacity(
    active,
    capacity,
    @relation.execution_capacity_retained_bytes(quote),
    @relation.execution_capacity_execution_bytes(quote),
  ).unwrap()
  assert_eq(
    @relation.advance_completed_relation_identity_scan(scan, 1).unwrap(),
    (false, 1),
  )
  assert_eq(@resources.ledger_limits(ledger), limits)
  assert_true(@relation.cancel_completed_relation_identity_scan(scan))
  assert_true(release_output(held))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}
