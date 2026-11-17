///|
test "Source identity quote includes retained encoder facts before construction" {
  let base = @execution.execution_capacity(100L, 200L).unwrap()
  let quoted = source_cell_identity_capacity(base).unwrap()
  // H11/R19/W11 = 416 logical bytes, including the new facts H2/R2/W5=88.
  // These are independent inventory counts, not runtime heap observations.
  assert_eq(@execution.execution_capacity_retained_bytes(quoted), 516L)
  assert_eq(@execution.execution_capacity_execution_bytes(quoted), 616L)
  assert_true(
    source_cell_identity_capacity(
      @execution.execution_capacity(9223372036854775392L, 9223372036854775807L).unwrap(),
    )
    is None,
  )
}
