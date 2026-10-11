///|
fn computation_capacity_test_ledger(
  retained : Int64,
  execution : Int64,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
}

///|
test "original computation funding keeps contract control and scratch distinct" {
  // These are exact test charges, not an adopted Native layout coefficient.
  let capacity : ResidentEffectComputationCapacity = {
    contract_bytes: 7L,
    control_bytes: 2L,
    workspace_bytes: 5L,
    max_utf16_units: 4096,
  }
  let ledger = computation_capacity_test_ledger(9L, 5L)
  let token = reserve_original_computation_capacity(ledger, capacity).unwrap()
  assert_true(@resources.capacity_reservation_matches(ledger, token, 9L, 5L))
  assert_false(@resources.capacity_reservation_matches(ledger, token, 7L, 5L))
  assert_false(
    @resources.capacity_reservation_matches(
      computation_capacity_test_ledger(9L, 5L),
      token,
      9L,
      5L,
    ),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_retention_bytes, 9L)
  assert_eq(usage.reserved_execution_bytes, 5L)
  assert_eq(usage.attempts, 0)
  assert_eq(usage.holdings, 0)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  // Reading the same nominal token does not reserve again or supply send work.
  assert_true(@resources.capacity_reservation_matches(ledger, token, 9L, 5L))
  assert_eq(@resources.ledger_usage(ledger), usage)
  @resources.settle_capacity(ledger, token).unwrap()
  assert_false(@resources.capacity_reservation_open(token))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "original computation funding refuses one short before additional retention" {
  let capacity : ResidentEffectComputationCapacity = {
    contract_bytes: 7L,
    control_bytes: 2L,
    workspace_bytes: 5L,
    max_utf16_units: 4096,
  }
  for (retained, execution) in [(8L, 5L), (9L, 4L)] {
    let ledger = computation_capacity_test_ledger(retained, execution)
    let before = @resources.ledger_usage(ledger)
    let result = reserve_original_computation_capacity(ledger, capacity)
    assert_true(
      if retained == 8L {
        result is Err(RetentionLimit)
      } else {
        result is Err(ExecutionLimit)
      },
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
}

///|
test "original computation funding rejects missing components and overflowing sum" {
  let ledger = computation_capacity_test_ledger(9L, 5L)
  let before = @resources.ledger_usage(ledger)
  for
    capacity in [
      {
        contract_bytes: 7L,
        control_bytes: 2L,
        workspace_bytes: 5L,
        max_utf16_units: 0,
      },
      {
        contract_bytes: 7L,
        control_bytes: 0L,
        workspace_bytes: 5L,
        max_utf16_units: 4096,
      },
      {
        contract_bytes: 0L,
        control_bytes: 2L,
        workspace_bytes: 5L,
        max_utf16_units: 4096,
      },
      {
        contract_bytes: 7L,
        control_bytes: 2L,
        workspace_bytes: 0L,
        max_utf16_units: 4096,
      },
      {
        contract_bytes: -1L,
        control_bytes: 2L,
        workspace_bytes: 5L,
        max_utf16_units: 4096,
      },
      {
        contract_bytes: 9223372036854775807L,
        control_bytes: 1L,
        workspace_bytes: 5L,
        max_utf16_units: 4096,
      },
    ] {
    assert_true(
      reserve_original_computation_capacity(ledger, capacity)
      is Err(InvalidCharge),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
}

///|
test "original computation text measurement is independent of Store wire bytes" {
  let contract = @publication.result_definition_contract(
    @publication.prepare_result_definition("sha256:" + "1".repeat(64), "é😀").unwrap(),
  )
  let wire_bytes = @utf8.encode(
    @publication.publication_contract_json(contract),
  ).length()
  assert_true(
    @publication.publication_contract_representation_extent(
      contract, 32, 8, wire_bytes,
    )
    is Err(Encoding),
  )
  let capacity : ResidentEffectComputationCapacity = {
    contract_bytes: 7L,
    control_bytes: 2L,
    workspace_bytes: 5L,
    max_utf16_units: 4096,
  }
  // Independent test charges are not pricing the actual Native contract. This
  // case checks selection of the measurement bound, not a funded layout.
  let extent = original_computation_contract_extent(contract, capacity, 32, 8).unwrap()
  assert_true(
    extent.contract_text_utf16_units + extent.canonical.text_utf16_units >
    wire_bytes.to_int64(),
  )
  assert_eq(extent.canonical.nodes, 5L)
  assert_eq(extent.contract_strings, 4L)
}
