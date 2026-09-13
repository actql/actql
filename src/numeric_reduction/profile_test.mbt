///|
test "pinned profile admission and explicit members retain their exact owner" {
  let bytes = fixture()
  let pin = "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
  let p = admit(bytes, pin, bytes.length()).unwrap()
  let other = admit(bytes, pin, bytes.length()).unwrap()
  assert_eq(cid(p), pin)
  assert_eq(admitted_bytes(p), bytes.length())
  assert_eq(member_count(p), 2)
  for
    (index, expected, kind) in [
      (
        0,
        "sha256:4077bb93149235757642468a512543d949f48d5a81f04f49827193f3e9420f55",
        Algorithm::LeftFold,
      ),
      (
        1,
        "sha256:48158d55d2a97e7c1d3ea95c8b7e085469eedc6186f24b57427aa8e610dceeba",
        Algorithm::AdjacentPairs,
      ),
    ] {
    assert_eq(member_cid_at(p, index), Some(expected))
    let selected = select(p, expected).unwrap()
    assert_eq(algorithm(selected), kind)
    assert_eq(reduction_cid(selected), expected)
    assert_true(physical_equal(reduction_profile(selected), p))
    assert_false(physical_equal(reduction_profile(selected), other))
  }
  for index in [-1, 2, 2147483647] {
    assert_true(member_cid_at(p, index) is None)
  }
  assert_true(select(p, pin) is Err(UnknownMember))
  assert_true(select(p, "left_fold") is Err(UnknownMember))
  assert_true(admit(bytes, pin, bytes.length() - 1) is Err(BudgetExceeded))
  assert_true(admit(bytes, pin, -1) is Err(InvalidLimits))
  assert_true(
    admit(bytes, member_cid_at(p, 0).unwrap(), bytes.length())
    is Err(UnsupportedProfile),
  )
}

///|
test "self-consistent or noncanonical bodies cannot substitute for a supported profile" {
  let original = fixture()
  let pin = "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
  let text = @utf8.decode(original)
  for
    body in [
      "{}",
      text + "\n",
      text.replace(old="reject_any_nonfinite", new="accept_any_nonfinite"),
    ] {
    let bytes = @utf8.encode(body)
    assert_true(admit(bytes, pin, bytes.length()) is Err(IdentityMismatch))
    assert_true(
      admit(bytes, "sha256:" + @sha.hex(bytes), bytes.length())
      is Err(UnsupportedProfile),
    )
  }
}
