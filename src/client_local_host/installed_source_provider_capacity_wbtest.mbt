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
