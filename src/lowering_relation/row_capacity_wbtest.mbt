///|
test "declared Join output bound is separate from input counts" {
  assert_eq(declared_join_row_bound(Some(@join.Literal(2000L)), 2), Some(2000))
  assert_eq(declared_join_row_bound(Some(@join.Literal(1L)), 2), Some(1))
  assert_eq(declared_join_row_bound(Some(@join.Literal(2147483647L)), 2), Some(2147483647))
}
///|
test "declared Join output bound declines missing bound parameters and representation overflow" {
  assert_eq(declared_join_row_bound(None, 2), None)
  assert_eq(declared_join_row_bound(Some(@join.Parameter("limit")), 2), None)
  for rows in [-1L, 0L, 2147483648L, 9223372036854775807L] {
    assert_eq(declared_join_row_bound(Some(@join.Literal(rows)), 2), None)
  }
  for ports in [0, 1, 3] {
    assert_eq(declared_join_row_bound(Some(@join.Literal(10L)), ports), None)
  }
}

///|
test "intrinsic joins account for unmatched rows and empty sides" {
  for (left,right) in [(0,0),(0,3),(3,0),(2,3),(1,1)] {
    assert_eq(intrinsic_join_row_bound(@join.Inner,None,[left,right]),Some(left*right))
    assert_eq(intrinsic_join_row_bound(@join.Left,None,[left,right]),Some(left*Int::max(1,right)))
    assert_eq(intrinsic_join_row_bound(@join.Right,None,[left,right]),Some(Int::max(1,left)*right))
    assert_eq(intrinsic_join_row_bound(@join.Semi,None,[left,right]),Some(left))
    assert_eq(intrinsic_join_row_bound(@join.Anti,None,[left,right]),Some(left))
  }
}
///|
test "intrinsic join bounds preserve guard minima and representation limits" {
  assert_eq(intrinsic_join_row_bound(@join.Inner,Some(@join.Literal(3L)),[2,3]),Some(3))
  assert_eq(intrinsic_join_row_bound(@join.Left,Some(@join.Literal(2000L)),[1,0]),Some(1))
  assert_eq(intrinsic_join_row_bound(@join.Inner,Some(@join.Parameter("limit")),[2,3]),Some(6))
  assert_eq(intrinsic_join_row_bound(@join.Inner,None,[2147483647,2147483647]),None)
  assert_eq(intrinsic_join_row_bound(@join.Inner,Some(@join.Literal(100L)),[2147483647,2147483647]),Some(100))
  assert_eq(intrinsic_join_row_bound(@join.Right,None,[0,2147483647]),Some(2147483647))
  assert_eq(intrinsic_join_row_bound(@join.Left,None,[-1,1]),None)
  assert_eq(intrinsic_join_row_bound(@join.Inner,None,[1]),None)
  assert_eq(intrinsic_join_row_bound(@join.Inner,Some(@join.Literal(0L)),[1,1]),None)
}
