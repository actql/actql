///|
test "preparation representation tariff keeps units and checks complete logical sum" {
  let record : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 3L,
    owned_utf16_units: 4L,
    owned_wire_bytes: 5L,
  }
  assert_eq(preparation_representation_cost(record), Some(69L))
  assert_true(
    preparation_representation_cost({ ..record, record_headers: -1L, }) is None,
  )
  assert_true(
    preparation_representation_cost({
      ..record,
      reference_slots: 9223372036854775807L,
    })
    is None,
  )
  let zero : PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  assert_eq(
    preparation_representation_cost({
      ..zero,
      owned_wire_bytes: 9223372036854775807L,
    }),
    Some(9223372036854775807L),
  )
  assert_true(
    preparation_representation_cost({
      ..zero,
      record_headers: 1L,
      owned_wire_bytes: 9223372036854775807L,
    })
    is None,
  )
  // Shared backing is included once at its owner; two borrowing fields are
  // two reference slots, not two copies of the owner's UTF16 payload.
  assert_eq(
    preparation_representation_cost({
      ..zero,
      reference_slots: 2L,
      owned_utf16_units: 100L,
    }),
    Some(216L),
  )
}

///|
test "preparation representation tariff deterministic unit and boundary properties" {
  let zero : PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for n in 0..<129 {
    let n = n.to_int64()
    let combined = {
      record_headers: n,
      reference_slots: n,
      scalar_words: n,
      owned_utf16_units: n,
      owned_wire_bytes: n,
    }
    let a = preparation_representation_cost({ ..zero, record_headers: n, }).unwrap()
    let b = preparation_representation_cost({ ..zero, reference_slots: n, }).unwrap()
    let c = preparation_representation_cost({ ..zero, scalar_words: n, }).unwrap()
    let d = preparation_representation_cost({ ..zero, owned_utf16_units: n, }).unwrap()
    let e = preparation_representation_cost({ ..zero, owned_wire_bytes: n, }).unwrap()
    assert_eq(
      preparation_representation_cost(combined),
      Some(a + b + c + d + e),
    )
    let base = preparation_representation_cost(combined).unwrap()
    assert_eq(
      preparation_representation_cost({ ..combined, reference_slots: n + 1L, }),
      Some(base + 8L),
    )
    assert_eq(
      preparation_representation_cost({ ..combined, owned_utf16_units: n + 1L, }),
      Some(base + 2L),
    )
  }
  let max = 9223372036854775807L
  assert_eq(
    preparation_representation_cost({ ..zero, reference_slots: max / 8L, }),
    Some(max - 7L),
  )
  assert_true(
    preparation_representation_cost({ ..zero, reference_slots: max / 8L + 1L, })
    is None,
  )
  assert_eq(
    preparation_representation_cost({
      ..zero,
      reference_slots: max / 8L,
      owned_wire_bytes: 7L,
    }),
    Some(max),
  )
  assert_true(
    preparation_representation_cost({
      ..zero,
      reference_slots: max / 8L,
      owned_wire_bytes: 8L,
    })
    is None,
  )
  for
    invalid in [
      { ..zero, reference_slots: -1L, },
      { ..zero, scalar_words: -1L, },
      { ..zero, owned_utf16_units: -1L, },
      { ..zero, owned_wire_bytes: -1L, },
    ] {
    assert_true(preparation_representation_cost(invalid) is None)
  }
}

///|
test "preparation representation owner reconciliation deduplicates identity not copied contents" {
  let original = [1, 2]
  let copy = original.copy()
  let units : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let cost = preparation_representation_cost(units).unwrap()
  assert_eq(
    _preparation_owned_representation_cost(
      [(original, units), (original, units)],
      3,
    ),
    Some(cost),
  )
  assert_eq(
    _preparation_owned_representation_cost(
      [(original, units), (copy, units)],
      3,
    ),
    Some(2L * cost),
  )
  assert_true(
    _preparation_owned_representation_cost(
      [(original, units), (copy, units)],
      2,
    )
    is None,
  )
  assert_true(
    _preparation_owned_representation_cost(
      [(original, units), (original, { ..units, reference_slots: 3L, })],
      3,
    )
    is None,
  )
  // A constructor coexistence upper bound covers the reconciled owner costs.
  let bound = {
    ..units,
    record_headers: 2L,
    reference_slots: 4L,
    scalar_words: 2L,
  }
  assert_eq(
    _preparation_owned_representation_cost(
      [(original, units), (copy, units)],
      3,
    ),
    preparation_representation_cost(bound),
  )
}

///|
test "shared preparation execution fold prices original inventories with one checked tariff" {
  let zero : PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let inventory : PreparationExecutionInventory = {
    retained: {
      record_headers: 1L,
      reference_slots: 2L,
      scalar_words: 3L,
      owned_utf16_units: 4L,
      owned_wire_bytes: 5L,
    },
    workspace: { ..zero, scalar_words: 2L, },
    retained_nodes: 2L,
    workspace_nodes: 3L,
    retained_bytes: 7L,
    workspace_bytes: 11L,
  }
  let capacity = _preparation_execution_capacity(inventory).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 588L)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), 1383L)
  let max = 9223372036854775807L
  let exact : PreparationExecutionInventory = {
    retained: zero,
    workspace: zero,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: max,
    workspace_bytes: 0L,
  }
  let maximum = _preparation_execution_capacity(exact).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(maximum), max)
  assert_eq(@execution.execution_capacity_execution_bytes(maximum), max)
  assert_true(
    _preparation_execution_capacity({ ..exact, workspace_bytes: 1L, }) is None,
  )
  for
    changed in [
      { ..inventory, retained_nodes: -1L, },
      { ..inventory, workspace_nodes: -1L, },
      { ..inventory, retained_bytes: -1L, },
      { ..inventory, workspace_bytes: -1L, },
      { ..inventory, retained_nodes: max, },
      { ..inventory, workspace_nodes: max, },
      { ..inventory, retained: { ..zero, reference_slots: max, }, },
      { ..inventory, workspace: { ..zero, owned_utf16_units: max, }, },
    ] {
    assert_true(_preparation_execution_capacity(changed) is None)
  }
}
