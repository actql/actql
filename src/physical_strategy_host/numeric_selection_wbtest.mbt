///|
test "numeric selection requires one exact member for the checked profile" {
  let profile = @numeric.builtin_profile()
  let profile_cid = @numeric.cid(profile)
  let left = @connector.numeric_reduction_support(
    profile_cid,
    @numeric.member_cid_at(profile, 0).unwrap(),
  ).unwrap()
  let pairs = @connector.numeric_reduction_support(
    profile_cid,
    @numeric.member_cid_at(profile, 1).unwrap(),
  ).unwrap()
  assert_true(select_declared_numeric_member(profile, []) is None)
  let selected = select_declared_numeric_member(profile, [left]).unwrap()
  assert_eq(
    @numeric.reduction_cid(selected),
    @numeric.member_cid_at(profile, 0).unwrap(),
  )
  assert_true(select_declared_numeric_member(profile, [left, pairs]) is None)
  let unknown = @connector.numeric_reduction_support(
    profile_cid, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  ).unwrap()
  assert_true(select_declared_numeric_member(profile, [unknown]) is None)
}

///|
test "numeric occurrence slots become immutable when sealed" {
  let counts : Array[Int?] = [None, Some(0), Some(2)]
  assert_true(numeric_reduction_slot_open(counts, 0))
  assert_false(numeric_reduction_slot_open(counts, 1))
  assert_false(numeric_reduction_slot_open(counts, 2))
  assert_false(numeric_reduction_slot_open(counts, 3))
  assert_eq(counts, [None, Some(0), Some(2)])
}

///|
test "materializing completion requires every selected numeric slot to seal" {
  assert_true(numeric_reductions_ready_for_completion(0, false))
  assert_false(numeric_reductions_ready_for_completion(1, false))
  assert_false(numeric_reductions_ready_for_completion(2, false))
  assert_true(numeric_reductions_ready_for_completion(2, true))
}
