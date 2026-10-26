///|
/// Reconcile one typed owner family in one immutable phase snapshot. The
/// inventory itself is borrowed, not allocated here. Equal content is not
/// identity: distinct copied owners are charged separately. Repeated identity
/// with different extents is not a valid immutable snapshot and refuses.
fn[T] preparation_owned_representation_cost(
  owners : Array[(T, @execution.PreparationRepresentationUnits)],
  max_work : Int,
) -> Int64? {
  if max_work < 0 {
    return None
  }
  let mut remaining = max_work
  let mut total = 0L
  for index in 0..<owners.length() {
    if remaining == 0 {
      return None
    }
    remaining -= 1
    let (owner, units) = owners[index]
    let mut duplicate = false
    for earlier in 0..<index {
      if remaining == 0 {
        return None
      }
      remaining -= 1
      let (previous, extent) = owners[earlier]
      if physical_equal(owner, previous) {
        if units != extent {
          return None
        }
        duplicate = true
        break
      }
    }
    if !duplicate {
      guard @execution.preparation_representation_cost(units) is Some(cost) else {
        return None
      }
      if cost > 9223372036854775807L - total {
        return None
      }
      total += cost
    }
  }
  Some(total)
}

///|
test "preparation representation tariff keeps units and checks complete logical sum" {
  let record : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 3L,
    owned_utf16_units: 4L,
    owned_wire_bytes: 5L,
  }
  assert_eq(@execution.preparation_representation_cost(record), Some(69L))
  assert_true(
    @execution.preparation_representation_cost({
      ..record,
      record_headers: -1L,
    })
    is None,
  )
  assert_true(
    @execution.preparation_representation_cost({
      ..record,
      reference_slots: 9223372036854775807L,
    })
    is None,
  )
  let zero : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  assert_eq(
    @execution.preparation_representation_cost({
      ..zero,
      owned_wire_bytes: 9223372036854775807L,
    }),
    Some(9223372036854775807L),
  )
  assert_true(
    @execution.preparation_representation_cost({
      ..zero,
      record_headers: 1L,
      owned_wire_bytes: 9223372036854775807L,
    })
    is None,
  )
  // Shared backing is included once at its owner; two borrowing fields are
  // two reference slots, not two copies of the owner's UTF16 payload.
  assert_eq(
    @execution.preparation_representation_cost({
      ..zero,
      reference_slots: 2L,
      owned_utf16_units: 100L,
    }),
    Some(216L),
  )
}

///|
test "preparation representation tariff deterministic unit and boundary properties" {
  let zero : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for n in 0..<129 {
    let n = n.to_int64()
    let combined : @execution.PreparationRepresentationUnits = {
      record_headers: n,
      reference_slots: n,
      scalar_words: n,
      owned_utf16_units: n,
      owned_wire_bytes: n,
    }
    let a = @execution.preparation_representation_cost({
      ..zero,
      record_headers: n,
    }).unwrap()
    let b = @execution.preparation_representation_cost({
      ..zero,
      reference_slots: n,
    }).unwrap()
    let c = @execution.preparation_representation_cost({
      ..zero,
      scalar_words: n,
    }).unwrap()
    let d = @execution.preparation_representation_cost({
      ..zero,
      owned_utf16_units: n,
    }).unwrap()
    let e = @execution.preparation_representation_cost({
      ..zero,
      owned_wire_bytes: n,
    }).unwrap()
    assert_eq(
      @execution.preparation_representation_cost(combined),
      Some(a + b + c + d + e),
    )
    let base = @execution.preparation_representation_cost(combined).unwrap()
    assert_eq(
      @execution.preparation_representation_cost({
        ..combined,
        reference_slots: n + 1L,
      }),
      Some(base + 8L),
    )
    assert_eq(
      @execution.preparation_representation_cost({
        ..combined,
        owned_utf16_units: n + 1L,
      }),
      Some(base + 2L),
    )
  }
  let max = 9223372036854775807L
  assert_eq(
    @execution.preparation_representation_cost({
      ..zero,
      reference_slots: max / 8L,
    }),
    Some(max - 7L),
  )
  assert_true(
    @execution.preparation_representation_cost({
      ..zero,
      reference_slots: max / 8L + 1L,
    })
    is None,
  )
  assert_eq(
    @execution.preparation_representation_cost({
      ..zero,
      reference_slots: max / 8L,
      owned_wire_bytes: 7L,
    }),
    Some(max),
  )
  assert_true(
    @execution.preparation_representation_cost({
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
    assert_true(@execution.preparation_representation_cost(invalid) is None)
  }
}

///|
test "preparation representation owner reconciliation deduplicates identity not copied contents" {
  let original = [1, 2]
  let copy = original.copy()
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let cost = @execution.preparation_representation_cost(units).unwrap()
  assert_eq(
    preparation_owned_representation_cost(
      [(original, units), (original, units)],
      3,
    ),
    Some(cost),
  )
  assert_eq(
    preparation_owned_representation_cost([(original, units), (copy, units)], 3),
    Some(2L * cost),
  )
  assert_true(
    preparation_owned_representation_cost([(original, units), (copy, units)], 2)
    is None,
  )
  assert_true(
    preparation_owned_representation_cost(
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
    preparation_owned_representation_cost([(original, units), (copy, units)], 3),
    @execution.preparation_representation_cost(bound),
  )
}

///|
test "shared preparation execution fold prices original inventories with one checked tariff" {
  let zero : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let inventory : @execution.PreparationExecutionInventory = {
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
  let capacity = @execution.preparation_execution_capacity(inventory).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 588L)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), 1383L)
  let max = 9223372036854775807L
  let exact : @execution.PreparationExecutionInventory = {
    retained: zero,
    workspace: zero,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: max,
    workspace_bytes: 0L,
  }
  let maximum = @execution.preparation_execution_capacity(exact).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(maximum), max)
  assert_eq(@execution.execution_capacity_execution_bytes(maximum), max)
  assert_true(
    @execution.preparation_execution_capacity({ ..exact, workspace_bytes: 1L, })
    is None,
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
    assert_true(@execution.preparation_execution_capacity(changed) is None)
  }
}
