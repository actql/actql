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
