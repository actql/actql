///|
// Independent unchanged-domain arithmetic boundaries, not execution backing,
// a minimal profile, physical allocation or authority/retirement evidence.
test "provider inventory keeps original generation bounds and exact Int64 edge" {
  let base = @execution.execution_capacity(11L, 13L).unwrap()
  let ordinary = provider_capacity(base, 7L, 3).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(ordinary), 11L)
  assert_eq(@execution.execution_capacity_execution_bytes(ordinary), 34L)
  let exact = provider_capacity(base, 3074457345618258598L, 3).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(exact), 11L)
  assert_eq(
    @execution.execution_capacity_execution_bytes(exact),
    9223372036854775807L,
  )
  assert_true(provider_capacity(base, -1L, 1) is None)
  assert_true(provider_capacity(base, 0L, 0) is None)
  assert_true(provider_capacity(base, 0L, -1) is None)
  assert_true(provider_capacity(base, 3074457345618258599L, 3) is None)
  assert_eq(
    @execution.execution_capacity_execution_bytes(
      provider_capacity(base, 0L, 2147483647).unwrap(),
    ),
    13L,
  )
}
