///|
test "exact decimal coefficients add without bounded integer conversion" {
  let control = { remaining: 10000, max_frames: 0, }
  let workspace = row_workspace(1000)
  let add = fn(left : String, right : String) -> String {
    add_decimal_coefficients(left, right, control, workspace).unwrap()
  }
  assert_eq(
    add("99999999999999999999999999999999999999", "1"),
    "100000000000000000000000000000000000000",
  )
  assert_eq(
    add("100000000000000000000000000000000000000", "-1"),
    "99999999999999999999999999999999999999",
  )
  assert_eq(add("-999", "1000"), "1")
  assert_eq(add("999", "-1000"), "-1")
  assert_eq(add("-50", "-50"), "-100")
  assert_eq(add("123456", "-123456"), "0")
  assert_eq(workspace.live, 0)
}

///|
test "exact decimal coefficient addition has an exact control boundary" {
  let exact_control = { remaining: 4, max_frames: 0, }
  let exact_workspace = row_workspace(2)
  guard add_decimal_coefficients("1", "2", exact_control, exact_workspace)
    is Ok(exact) else {
    fail("exact budget should succeed")
  }
  assert_eq(exact, "3")
  assert_eq(exact_control.remaining, 0)
  assert_eq(exact_workspace.live, 0)
  assert_true(
    add_decimal_coefficients(
      "1",
      "2",
      { remaining: 3, max_frames: 0, },
      row_workspace(2),
    )
    is Err(RowLimit),
  )
  assert_true(
    add_decimal_coefficients(
      "1",
      "2",
      { remaining: 4, max_frames: 0, },
      row_workspace(1),
    )
    is Err(RowLimit),
  )
}
