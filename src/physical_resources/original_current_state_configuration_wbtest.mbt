///|
fn current_configuration_test_limits() -> LedgerLimits {
  {
    planning_work: 17,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 100L,
    retained_bytes: 256L,
    execution_bytes: 256L,
  }
}

///|
test "current configuration DATA guard compares every independent limit without altering saved state" {
  let document = current_document_test_read(current_document_test_wire())
  let expected = current_configuration_test_limits()
  let original = document.state
  assert_true(
    check_original_current_state_document_configuration(
      document,
      expected,
      None,
    )
    is Ok(_),
  )
  for
    wrong in [
      { ..expected, planning_work: 18, },
      { ..expected, attempts: 17, },
      { ..expected, holdings: 17, },
      { ..expected, transfer_bytes: 101L, },
      { ..expected, retained_bytes: 257L, },
      { ..expected, execution_bytes: 257L, },
    ] {
    assert_true(
      check_original_current_state_document_configuration(document, wrong, None)
      is Err(InvalidRecord),
    )
    assert_true(document.state == original)
    assert_true(document.source is Some(_))
  }
  assert_true(
    check_original_current_state_document_configuration(
      document,
      expected,
      Some({ tokens: 0L, cost_units: 0L, duration_ms: 0L, }),
    )
    is Err(InvalidRecord),
  )
  assert_true(document.state == original)
  retire_original_current_state_document(document)
}

///|
test "current configuration DATA guard does not refill unknown or consumed-overrun quantities" {
  // Independent header data: this deliberately proves only configuration
  // comparison, NOT authenticated token conservation or original admission.
  // Existing observation rules preserve overrun and uncertain usage rather
  // than erasing them because they exceed an installed quantity allowance.
  let wire = current_document_test_wire().replace(
    old="null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]]",
    new="[\"13\",\"17\",\"19\"],[[\"0\",\"0\",\"0\"],[\"13\",\"17\",\"19\"],[\"23\",\"0\",\"0\"]]",
  )
  let document = current_document_test_read(wire)
  let original = document.state
  let expected : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  assert_true(
    check_original_current_state_document_configuration(
      document,
      current_configuration_test_limits(),
      Some(expected),
    )
    is Ok(_),
  )
  for
    wrong in [
      None,
      Some({ ..expected, tokens: 14L, }),
      Some({ ..expected, cost_units: 18L, }),
      Some({ ..expected, duration_ms: 20L, }),
    ] {
    assert_true(
      check_original_current_state_document_configuration(
        document,
        current_configuration_test_limits(),
        wrong,
      )
      is Err(InvalidRecord),
    )
  }
  assert_true(document.state == original)
  assert_eq(document.state.quantities.uncertain, expected)
  assert_eq(document.state.quantities.consumed.tokens, 23L)
  assert_eq(document.state.next_capacity_serial, Some(-3))
  assert_true(document.source is Some(_))
  retire_original_current_state_document(document)
}

///|
test "current configuration DATA guard rejects retired document without creating original custody" {
  let document = current_document_test_read(current_document_test_wire())
  let original = document.state
  retire_original_current_state_document(document)
  assert_true(
    check_original_current_state_document_configuration(
      document,
      current_configuration_test_limits(),
      None,
    )
    is Err(Terminal),
  )
  assert_true(document.state == original)
  assert_true(document.source is None)
}
