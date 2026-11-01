///|
test "same Source native constructor quantities remain retained through original material retirement" {
  let source = @execution.execution_capacity(11L, 13L).unwrap()
  let provider = @execution.execution_capacity(5L, 7L).unwrap()
  let combined = compose_installed_source_construction_capacity(source, [
    provider,
  ]).unwrap()
  // Native peak7 is retained on this SAME Source, not just provider's5
  // output or an unbacked later callback. Shared addition owns overflow.
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 18L)
  assert_eq(@execution.execution_capacity_execution_bytes(combined), 20L)
  let same = compose_installed_source_construction_capacity(source, []).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(same), 11L)
  assert_eq(@execution.execution_capacity_execution_bytes(same), 13L)
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(
    compose_installed_source_construction_capacity(source, [maximum]) is None,
  )
}

///|
test "retained Source constructor DATA cannot invent a completion or refund original work" {
  let original = @execution.execution_capacity(5L, 7L).unwrap()
  let retained = retained_installed_source_construction_capacity(original)
  assert_eq(@execution.execution_capacity_retained_bytes(original), 5L)
  assert_eq(@execution.execution_capacity_execution_bytes(original), 7L)
  assert_eq(@execution.execution_capacity_retained_bytes(retained), 5L)
  assert_eq(@execution.execution_capacity_execution_bytes(retained), 5L)
  let before = compose_installed_source_construction_capacity(
    @execution.execution_capacity(11L, 13L).unwrap(),
    [original],
  ).unwrap()
  let after = compose_installed_source_construction_capacity(
    @execution.execution_capacity(11L, 13L).unwrap(),
    [retained],
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(before), 18L)
  assert_eq(@execution.execution_capacity_execution_bytes(before), 20L)
  assert_eq(@execution.execution_capacity_retained_bytes(after), 16L)
  assert_eq(@execution.execution_capacity_execution_bytes(after), 18L)
}
