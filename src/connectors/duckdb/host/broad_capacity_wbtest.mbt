///|
fn broad_capacity_test_limits() -> BroadHostLimits {
  {
    physical: { max_rows: 1, max_cells: 1, max_nodes: 1, max_text_bytes: 1, },
    metadata_work: 1,
    retention: { max_nodes: 1, max_text_bytes: 1, max_depth: 1, max_work: 1, },
    transport: {
      max_bytes: 1,
      max_nodes: 1,
      max_columns: 1,
      max_rows: 1,
      max_text_bytes: 1,
    },
    completion: {
      execution: {
        rows: {
          max_rows: 1,
          metadata_entries: 1,
          retained_entries: 1,
          operation_entries: 1,
          input_values: {
            max_nodes: 1,
            max_text_bytes: 1,
            max_depth: 1,
            max_work: 1,
          },
          output_values: {
            max_nodes: 1,
            max_text_bytes: 1,
            max_depth: 1,
            max_work: 1,
          },
        },
        max_work: 1,
        max_frames: 1,
      },
      guards: { max_work: 1, max_bytes: 1, max_nodes: 1, max_depth: 1, },
      retention: {
        received_wire_bytes: 1,
        retained_wire_bytes: 1,
        measurement: {
          max_columns: 1,
          max_order_work: 1,
          max_bytes: 1,
          max_nodes: 1,
          max_depth: 1,
        },
      },
      records: {
        max_work: 1,
        max_fields: 1,
        max_parameters: 1,
        max_bytes: 1,
        max_nodes: 1,
        max_depth: 1,
      },
      capture: { max_bytes: 1, max_nodes: 1, max_depth: 1, },
    },
  }
}

///|
test "Broad capacity retains scan, residual and evidence and rejects overflow" {
  let l = broad_capacity_test_limits()
  let residual = @execution.execution_capacity(512L, 1024L).unwrap()
  let capacity = broad_capacity(l, residual).unwrap()
  // Independently enumerated: 11 retained structural allowances and 7 text
  // allowances, plus 13 scratch structural and 4 scratch text allowances.
  assert_eq(capacity.retained_bytes, 3384L)
  assert_eq(capacity.execution_bytes, 4384L)
  let wider_scan = broad_capacity(
    { ..l, physical: { ..l.physical, max_nodes: 2, }, },
    residual,
  ).unwrap()
  assert_eq(wider_scan.retained_bytes, 3640L)
  assert_eq(wider_scan.execution_bytes, 4384L)
  let wider_residual = broad_capacity(
    l,
    @execution.execution_capacity(1024L, 2048L).unwrap(),
  ).unwrap()
  assert_eq(wider_residual.retained_bytes, 3896L)
  assert_eq(wider_residual.execution_bytes, 5408L)
  assert_true(
    broad_capacity(
      { ..l, transport: { ..l.transport, max_columns: -1, }, },
      residual,
    )
    is None,
  )
  assert_true(
    broad_capacity(
      l,
      @execution.execution_capacity(9223372036854775807L, 9223372036854775807L).unwrap(),
    )
    is None,
  )
}

///|
test "Broad phase peak keeps the scan alongside physical transport and full later Core" {
  let l = broad_capacity_test_limits()
  let full = broad_capacity(
    l,
    @execution.execution_capacity(512L, 10000L).unwrap(),
  ).unwrap()
  // Seven receiving structural occurrences, two text occurrences; the entire
  // original non-residual scratch remains present even before completion.
  assert_eq(broad_receiving_retention(l), Some(1808L))
  assert_eq(broad_receiving_scratch(l), Some(3360L))
  let peak = broad_physical_capacity(l, full, 10000L).unwrap()
  assert_eq(peak.retained_bytes, full.retained_bytes)
  assert_eq(peak.execution_bytes, 15168L)
  assert_eq(full.execution_bytes, 13360L)
  // A larger later residual remains funded from entry, including an empty
  // physical leg. This is a phase quote, never an early disposal acknowledgement.
  assert_eq(
    broad_physical_capacity(l, full, 0L).unwrap().execution_bytes,
    13360L,
  )
  assert_true(broad_physical_capacity(l, full, -1L) is None)
  assert_true(broad_physical_capacity(l, full, 9223372036854775807L) is None)
}

///|
test "Broad phase reservation preserves pending scan debt and the same consumed attempt" {
  let l = broad_capacity_test_limits()
  let full = broad_capacity(
    l,
    @execution.execution_capacity(512L, 10000L).unwrap(),
  ).unwrap()
  let peak = broad_physical_capacity(l, full, 10000L).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 20L,
    retained_bytes: 10000L,
    execution_bytes: 16384L,
  }).unwrap()
  let parent = @resources.reserve_capacity(ledger, 1000L, 1000L).unwrap()
  let before = @resources.ledger_usage(ledger)
  // The old simultaneous DB+future-Core sum refuses without spending an
  // attempt. The unchanged ledger admits the complete serial phase peak.
  assert_true(
    @resources.reserve_attempt(
      ledger,
      10L,
      full.retained_bytes,
      10000L + full.execution_bytes,
    )
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let original = @resources.reserve_attempt(
    ledger,
    10L,
    peak.retained_bytes,
    peak.execution_bytes,
  ).unwrap()
  @resources.consume_reserved_attempt(ledger, original).unwrap()
  @resources.charge_transfer(ledger, original, 2L).unwrap()
  let receiving = @resources.ledger_usage(ledger)
  assert_eq(receiving.reserved_execution_bytes, 16168L)
  assert_eq(receiving.reserved_retention_bytes, 4384L)
  // An unconfirmed/throwing cleanup keeps the full physical+scan peak. This
  // component exercises real Ledger semantics, not a physical-session ACK.
  @resources.mark_cleanup_pending(ledger, original).unwrap()
  assert_eq(@resources.ledger_usage(ledger), receiving)
  assert_true(@resources.reservation_pending(original))
  // The adapter may make this existing transition only after its SAME native
  // session owner confirms cleanup. All retained scan/evidence debt stays live.
  @resources.settle_execution_reservation(
    ledger,
    original,
    remaining_execution=full.execution_bytes,
  ).unwrap()
  let residual = @resources.ledger_usage(ledger)
  assert_eq(residual.reserved_execution_bytes, 14360L)
  assert_eq(residual.reserved_retention_bytes, 4384L)
  assert_eq(residual.attempts, 1)
  assert_eq(residual.transferred_bytes, 2L)
  assert_eq(residual.live_reservations, receiving.live_reservations)
  let holding = @resources.retain_allocation(
    ledger,
    original,
    full.retained_bytes,
  ).unwrap()
  @resources.settle_reservation(ledger, original).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, full.retained_bytes)
  @resources.release_allocation(ledger, holding).unwrap()
  @resources.settle_capacity(ledger, parent).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.attempts, 1)
  assert_eq(closed.transferred_bytes, 2L)
}
