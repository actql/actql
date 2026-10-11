///|
fn computation_test_extent() -> @publication.PublicationRepresentationExtent {
  {
    contract_records: 1L,
    contract_strings: 4L,
    contract_text_utf16_units: 10L,
    canonical: {
      nodes: 3L,
      strings: 2L,
      text_utf16_units: 5L,
      arrays: 1L,
      objects: 1L,
      array_backing_slots: 4L,
      object_backing_slots: 8L,
      max_frame_slots: 2L,
    },
  }
}

///|
test "original extent accounts for all strings nodes and actual spare backing" {
  // Independent arithmetic: 5 + 28 + 20 + 9 + 14 + 10 + 11 + 13 + 68 + 152.
  let extent = computation_test_extent()
  let layout = computation_test_layout()
  assert_eq(original_computation_extent_charge(extent, layout, 0L), Ok(330L))
  // Six repeated occurrences are not automatically sharing one lifetime charge.
  let mut total = 0L
  for _ in 0..<6 {
    total = original_computation_extent_charge(extent, layout, total).unwrap()
  }
  assert_eq(total, 1980L)
  let sparse = {
    ..extent,
    canonical: { ..extent.canonical, object_backing_slots: 1L, },
  }
  assert_eq(original_computation_extent_charge(sparse, layout, 0L), Ok(197L))
}

///|
test "positive envelopes cannot substitute for original representation charge" {
  let capacity : ResidentEffectComputationCapacity = {
    contract_bytes: 329L,
    control_bytes: 2L,
    workspace_bytes: 20L,
    max_utf16_units: 4096,
    layout: computation_test_layout(),
  }
  assert_true(original_computation_capacity_valid(capacity))
  assert_eq(original_computation_layout_admission(capacity, 0), Ok(()))
  assert_eq(
    original_computation_layout_admission({ ..capacity, control_bytes: 1L, }, 0),
    Err(RetentionLimit),
  )
  assert_eq(
    original_computation_layout_admission(
      { ..capacity, workspace_bytes: 19L, },
      0,
    ),
    Err(ExecutionLimit),
  )
  let charge = original_computation_extent_charge(
    computation_test_extent(),
    capacity.layout,
    0L,
  ).unwrap()
  assert_eq(charge, 330L)
  assert_true(charge > capacity.contract_bytes)
  let ledger = computation_capacity_test_ledger(331L, 20L)
  let token = reserve_original_computation_capacity(ledger, capacity).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 331L)
  // Refusal does not lose or prematurely settle the original responsibility.
  assert_true(@resources.capacity_reservation_matches(ledger, token, 331L, 20L))
  @resources.settle_capacity(ledger, token).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "layout arithmetic rejects negative quantities and overflowing sum product" {
  assert_eq(original_computation_add_charge(0L, -1L, 2L), Err(InvalidCharge))
  assert_eq(original_computation_add_charge(-1L, 1L, 2L), Err(InvalidCharge))
  assert_eq(original_computation_add_charge(0L, 1L, 0L), Err(InvalidCharge))
  assert_eq(
    original_computation_add_charge(0L, 4611686018427387904L, 2L),
    Err(InvalidCharge),
  )
  assert_eq(
    original_computation_add_charge(9223372036854775807L, 1L, 1L),
    Err(InvalidCharge),
  )
  assert_eq(
    original_computation_add_charge(9223372036854775806L, 1L, 1L),
    Ok(9223372036854775807L),
  )
  let bad = { ..computation_test_extent(), contract_records: -1L, }
  assert_eq(
    original_computation_extent_charge(bad, computation_test_layout(), 0L),
    Err(InvalidCharge),
  )
}

///|
test "scratch admission includes overlapping growth before original traversal" {
  let layout = computation_test_layout()
  assert_eq(original_computation_workspace_charge(layout, 0), Ok(20L))
  assert_eq(original_computation_workspace_charge(layout, 7), Ok(20L))
  assert_eq(original_computation_workspace_charge(layout, 8), Ok(36L))
  assert_eq(
    original_computation_workspace_charge(layout, -1),
    Err(InvalidCharge),
  )
  assert_eq(
    original_computation_workspace_charge(
      { ..layout, frame_slot_bytes: 9223372036854775807L, },
      0,
    ),
    Err(InvalidCharge),
  )
}
