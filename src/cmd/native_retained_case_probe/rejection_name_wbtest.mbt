///|
test "identity exhaustion remains an explicit retained-case refusal" {
  assert_eq(
    rejection_name(Some(@resources.IdentityOverflow)),
    "identity-overflow",
  )
  assert_eq(rejection_name(None), "feasible")
}
