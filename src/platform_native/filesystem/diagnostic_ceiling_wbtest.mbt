///|
test "explicit Root diagnostic ceiling refuses nonpositive input" {
  for limit in [0, -1] {
    assert_true(open_root("unopened", diagnostic_ceiling=Some(limit)) is Err(InvalidLimit))
    assert_true(open_private_root("unopened", diagnostic_ceiling=Some(limit)) is Err(InvalidLimit))
  }
}
