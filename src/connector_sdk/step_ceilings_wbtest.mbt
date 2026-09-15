///|
test "step ceiling declarations snapshot distinct occurrences without exposing mutable storage" {
  let supplied = [(1, 20L), (3, 7L)]
  let snapshot = snapshot_step_ceilings(supplied, 4).unwrap()
  supplied[0] = (1, 999L)
  supplied.clear()
  assert_eq(step_ceiling(snapshot, -1), None)
  assert_eq(step_ceiling(snapshot, 0), None)
  assert_eq(step_ceiling(snapshot, 1), Some(20L))
  assert_eq(step_ceiling(snapshot, 2), None)
  assert_eq(step_ceiling(snapshot, 3), Some(7L))
  assert_eq(step_ceiling(snapshot, 4), None)
  assert_eq(snapshot_step_ceilings([], 0), Some([]))
}

///|
test "step ceiling declarations reject duplicate reversed negative and outside occurrences" {
  for
    supplied in [
      [(-1, 1L)],
      [(0, -1L)],
      [(4, 1L)],
      [(1, 2L), (1, 1L)],
      [(3, 1L), (1, 1L)],
    ] {
    assert_eq(snapshot_step_ceilings(supplied, 4), None)
  }
  assert_eq(snapshot_step_ceilings([(0, 1L)], 0), None)
  assert_eq(snapshot_step_ceilings([], -1), None)
}
