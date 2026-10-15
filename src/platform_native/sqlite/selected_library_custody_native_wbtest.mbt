///|
test "selected SQLite Library rejects invalid limits before acquisition" {
  for limit in [-1L, 0L, 4095L, 2147483648L] {
    assert_true(
      load_current_component_with_custody("/unused", limit, 128)
      is Err(RefusedBeforeAcquisition(InvalidLimit)),
    )
  }
  assert_true(
    load_current_component_with_custody("/unused", 4096L, 0)
    is Err(RefusedBeforeAcquisition(InvalidLimit)),
  )
}

///|
test "selected SQLite Library rejects malformed private paths before acquisition" {
  for path in ["", "relative", "/bad\u{0}path"] {
    assert_true(
      load_current_component_with_custody(path, 4096L, 128)
      is Err(RefusedBeforeAcquisition(InvalidName)),
    )
  }
}

///|
test "selected SQLite Library refuses an unprovided original domain" {
  assert_true(
    load_current_component_with_custody("/unused", 4096L, 128)
    is Err(
      RefusedBeforeAcquisition(
        Physical("original SQLite read domain unavailable")
      )
    ),
  )
}
