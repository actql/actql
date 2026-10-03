///|
test "Host estimate constructor copies mutable input inventories" {
  let slots = [[0, 1]]
  let milliseconds = [Some(12L)]
  let quantities = [Some(137L), None, None]
  let estimate = client_duckdb_acquisition_estimate(
    slots, milliseconds, quantities,
  ).unwrap()
  slots[0][0] = 8
  milliseconds[0] = Some(99L)
  quantities[0] = Some(999L)
  assert_eq(estimate.estimates[0].work_slots, [0, 1])
  assert_eq(estimate.estimates[0].milliseconds, Some(12L))
  assert_eq(estimate.quantities.transfer_bytes, Some(137L))
}

///|
test "selection diagnostics snapshot estimates independently of later mutations" {
  let estimate = client_duckdb_acquisition_estimate([[0, 1]], [Some(12L)], [
    Some(137L),
    None,
    None,
  ]).unwrap()
  let snapshot = client_duckdb_estimate_json(estimate)
  let before = snapshot.stringify()
  estimate.estimates[0].work_slots[0] = 8
  estimate.estimates.push({ work_slots: [2], milliseconds: Some(99L), })
  assert_eq(snapshot.stringify(), before)
  assert_true(client_duckdb_estimate_json(estimate).stringify() != before)
}
