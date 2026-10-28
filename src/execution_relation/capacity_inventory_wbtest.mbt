///|
test "capacity inventory keeps typed objects multiplicity and overlap distinct" {
  let retained : Array[ExecutionCapacityItem] = [
    { unit: ValueNodeSlots, count: 2L, copies: 2, },
    { unit: CursorRootSlots, count: 3L, copies: 1, },
    { unit: DecodedTextBytes, count: 5L, copies: 1, },
    { unit: CanonicalWireBytes, count: 7L, copies: 1, },
    { unit: QuotedBytes, count: 11L, copies: 1, },
  ]
  let workspace : Array[ExecutionCapacityItem] = [
    { unit: CanonicalWireBytes, count: 1000L, copies: 1, },
  ]
  // Four actual value slots, three independent roots, five decoded text
  // units, seven wire units and eleven already-quoted bytes.
  let independent = execution_capacity_inventory(
    retained,
    workspace,
    SeparateDimensions,
  ).unwrap()
  assert_eq(independent.retained_bytes, 1899L)
  assert_eq(independent.execution_bytes, 8000L)
  let overlapping = execution_capacity_inventory(
    retained,
    workspace,
    RetainedAlongsideExecution,
  ).unwrap()
  assert_eq(overlapping.retained_bytes, 1899L)
  assert_eq(overlapping.execution_bytes, 9899L)
  let original = execution_capacity(1L, 2L).unwrap()
  let combined = add_execution_capacity(original, overlapping).unwrap()
  assert_eq(combined.retained_bytes, 1900L)
  assert_eq(combined.execution_bytes, 9901L)
  assert_eq(original.retained_bytes, 1L)
  assert_eq(original.execution_bytes, 2L)
}

///|
test "capacity inventory rejects invalid counts and checked Int64 overflow" {
  let units : Array[ExecutionCapacityUnit] = [
    ValueNodeSlots,
    CursorRootSlots,
    DecodedTextBytes,
    CanonicalWireBytes,
    QuotedBytes,
  ]
  for unit in units {
    assert_true(
      execution_capacity_inventory(
        [],
        [{ unit, count: -1L, copies: 0, }],
        SeparateDimensions,
      )
      is None,
    )
    assert_true(
      execution_capacity_inventory(
        [],
        [{ unit, count: 0L, copies: -1, }],
        SeparateDimensions,
      )
      is None,
    )
  }
  let maximum = 9223372036854775807L
  assert_eq(
    execution_capacity_inventory(
      [],
      [{ unit: QuotedBytes, count: maximum, copies: 1, }],
      SeparateDimensions,
    ).unwrap().execution_bytes,
    maximum,
  )
  let invalid : Array[Array[ExecutionCapacityItem]] = [
    [{ unit: QuotedBytes, count: maximum, copies: 2, }],
    [{ unit: ValueNodeSlots, count: maximum, copies: 1, }],
    [
      { unit: QuotedBytes, count: maximum, copies: 1, },
      { unit: QuotedBytes, count: 1L, copies: 1, },
    ],
  ]
  for items in invalid {
    assert_true(
      execution_capacity_inventory([], items, SeparateDimensions) is None,
    )
  }
  assert_true(
    execution_capacity_inventory(
      [{ unit: QuotedBytes, count: maximum, copies: 1, }],
      [{ unit: QuotedBytes, count: 1L, copies: 1, }],
      RetainedAlongsideExecution,
    )
    is None,
  )
  assert_eq(
    execution_capacity_inventory(
      [],
      [{ unit: ValueNodeSlots, count: maximum, copies: 0, }],
      SeparateDimensions,
    ).unwrap().execution_bytes,
    0L,
  )
}

///|
test "incremental capacity inventory preserves prior usage and exact byte boundaries" {
  let maximum = 9223372036854775807L
  assert_eq(execution_capacity_inventory_add(7L, QuotedBytes, 3L, 4), Some(19L))
  assert_eq(
    execution_capacity_inventory_add(7L, ValueNodeSlots, 2L, 3),
    Some(1543L),
  )
  assert_eq(
    execution_capacity_inventory_add(maximum, QuotedBytes, 0L, 1),
    Some(maximum),
  )
  assert_eq(
    execution_capacity_inventory_add(maximum, ValueNodeSlots, maximum, 0),
    Some(maximum),
  )
  assert_eq(
    execution_capacity_inventory_add(maximum - 6L, QuotedBytes, 3L, 2),
    Some(maximum),
  )
  assert_true(
    execution_capacity_inventory_add(maximum - 5L, QuotedBytes, 3L, 2) is None,
  )
  assert_true(execution_capacity_inventory_add(-1L, QuotedBytes, 0L, 0) is None)
  assert_true(execution_capacity_inventory_add(0L, QuotedBytes, -1L, 0) is None)
  assert_true(execution_capacity_inventory_add(0L, QuotedBytes, 0L, -1) is None)
  assert_true(
    execution_capacity_inventory_add(0L, ValueNodeSlots, maximum, 1) is None,
  )
}

///|
test "shared representation counts retain positive factors and checked full Int64 products" {
  let maximum = 9223372036854775807L
  assert_eq(checked_preparation_add_product(7L, 3L, 4L), Some(19L))
  assert_eq(checked_preparation_add_product(maximum, 0L, 1L), Some(maximum))
  assert_eq(checked_preparation_add_product(0L, maximum, 1L), Some(maximum))
  assert_eq(
    checked_preparation_add_product(maximum - 6L, 2L, 3L),
    Some(maximum),
  )
  assert_true(checked_preparation_add_product(maximum - 5L, 2L, 3L) is None)
  assert_true(checked_preparation_add_product(0L, maximum, 2L) is None)
  assert_true(checked_preparation_add_product(-1L, 0L, 1L) is None)
  assert_true(checked_preparation_add_product(0L, -1L, 1L) is None)
  assert_true(checked_preparation_add_product(0L, 0L, 0L) is None)
  assert_true(checked_preparation_add_product(0L, 0L, -1L) is None)
}
