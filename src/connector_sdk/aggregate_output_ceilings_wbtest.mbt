///|
test "aggregate output ceilings snapshot exact occurrences" {
  let items = aggregate_output_ceiling(
    1,
    "collected",
    array_items_output_unit(),
    7L,
  ).unwrap()
  let bytes = aggregate_output_ceiling(
    1,
    "joined",
    string_bytes_output_unit(),
    23L,
  ).unwrap()
  let supplied = [items, bytes]
  let snapshot = snapshot_aggregate_output_ceilings(supplied, 2).unwrap()
  supplied.clear()
  assert_eq(
    find_aggregate_output_ceiling(
      snapshot,
      1,
      "collected",
      array_items_output_unit(),
    ),
    Some(7L),
  )
  assert_eq(
    find_aggregate_output_ceiling(
      snapshot,
      1,
      "joined",
      string_bytes_output_unit(),
    ),
    Some(23L),
  )
  assert_eq(
    find_aggregate_output_ceiling(
      snapshot,
      1,
      "collected",
      string_bytes_output_unit(),
    ),
    None,
  )
}

///|
test "aggregate output ceilings reject invalid and duplicate occurrences" {
  assert_true(
    aggregate_output_ceiling(-1, "a", array_items_output_unit(), 1L)
    is Err(InvalidLimits),
  )
  assert_true(
    aggregate_output_ceiling(0, "a", array_items_output_unit(), -1L)
    is Err(InvalidLimits),
  )
  let value = aggregate_output_ceiling(0, "a", array_items_output_unit(), 1L).unwrap()
  let duplicate = aggregate_output_ceiling(
    0,
    "a",
    array_items_output_unit(),
    2L,
  ).unwrap()
  assert_true(snapshot_aggregate_output_ceilings([value, duplicate], 1) is None)
  assert_true(snapshot_aggregate_output_ceilings([value], 0) is None)
  assert_true(snapshot_aggregate_output_ceilings([], -1) is None)
}
