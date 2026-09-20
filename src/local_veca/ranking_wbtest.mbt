///|
test "ranking workspace checks every derived width" {
  assert_eq(ranking_workspace(0, 2147483647, 0, 0), None)
  assert_eq(ranking_workspace(0, 2147483632, 0, 0), None)
  assert_eq(ranking_workspace(1, 2147483631, 0, 0), None)
}

///|
test "ranking workspace retains exact and one-short boundaries" {
  let required = ranking_workspace(4, 1, 2, 3).unwrap()
  assert_eq(required, 106)
  assert_true(required - 1 < required)
}
