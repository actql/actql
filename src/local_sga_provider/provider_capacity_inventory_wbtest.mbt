///|
// Independent unchanged-domain arithmetic boundaries, not execution backing,
// a minimal profile, physical allocation or authority/retirement evidence.
test "provider inventory keeps original generation bounds and exact Int64 edge" {
  let base = @execution.execution_capacity(11L, 13L).unwrap()
  let ordinary = provider_capacity(base, 7L, 3, 5L).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(ordinary), 11L)
  assert_eq(@execution.execution_capacity_execution_bytes(ordinary), 39L)
  let exact = provider_capacity(base, 4611686018427387895L, 2, 4L).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(exact), 11L)
  assert_eq(
    @execution.execution_capacity_execution_bytes(exact),
    9223372036854775807L,
  )
  assert_true(provider_capacity(base, -1L, 1, 0L) is None)
  assert_true(provider_capacity(base, 0L, 1, -1L) is None)
  assert_true(provider_capacity(base, 0L, 0, 0L) is None)
  assert_true(provider_capacity(base, 0L, -1, 0L) is None)
  assert_true(provider_capacity(base, 4611686018427387896L, 2, 4L) is None)
  assert_true(provider_capacity(base, 4611686018427387895L, 2, 5L) is None)
  assert_eq(
    @execution.execution_capacity_execution_bytes(
      provider_capacity(base, 0L, 2147483647, 0L).unwrap(),
    ),
    13L,
  )
}
