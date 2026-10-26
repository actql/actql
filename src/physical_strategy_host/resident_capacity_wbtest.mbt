///|
test "resident copy and independent holding have distinct admitted ceilings" {
  let capacity : @connector.ExecutionCapacity = {
    transfer_bytes: 1000L,
    retained_bytes: 20L,
    scratch_bytes: 10L,
    execution_bytes: 100L,
  }
  // A large shared copy can coexist with a smaller independently held output.
  // Common start still allocates that copy within its exact live environment.
  assert_true(resident_storage_capacity_matches(capacity, 100L, 20L, 10L, 100L))
  assert_false(
    resident_storage_capacity_matches(capacity, 101L, 20L, 10L, 100L),
  )
  assert_false(
    resident_storage_capacity_matches(capacity, 100L, 21L, 10L, 100L),
  )
  assert_false(
    resident_storage_capacity_matches(capacity, 100L, 20L, 11L, 100L),
  )
  // Neither allowance compensates for exceeding the other.
  assert_false(resident_storage_capacity_matches(capacity, 0L, 21L, 0L, 100L))
  assert_false(resident_storage_capacity_matches(capacity, 101L, 0L, 0L, 100L))
  assert_false(resident_storage_capacity_matches(capacity, -1L, 20L, 10L, 100L))
  assert_false(
    resident_storage_capacity_matches(capacity, 100L, -1L, 10L, 100L),
  )
}
