///|
test "numeric reduction declarations retain exact pinned identities" {
  let profile = "sha256:" + "1".repeat(64)
  let member_cid = "sha256:" + "a".repeat(64)
  let support = numeric_reduction_support(profile, member_cid).unwrap()
  assert_eq(numeric_reduction_support_profile_cid(support), profile)
  assert_eq(numeric_reduction_support_member_cid(support), member_cid)
  for
    invalid in [
      "",
      "sha256:" + "0".repeat(63),
      "sha256:" + "A".repeat(64),
      "sha512:" + "0".repeat(64),
    ] {
    assert_true(
      numeric_reduction_support(invalid, member_cid) is Err(InvalidLimits),
    )
    assert_true(
      numeric_reduction_support(profile, invalid) is Err(InvalidLimits),
    )
  }
}
