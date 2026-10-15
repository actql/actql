///|
test "selected SQLite Library does not enable a non-Native fallback" {
  assert_true(
    load_current_component_with_custody("/unused", 4096L, 128)
    is Err(RefusedBeforeAcquisition(UnsupportedTarget)),
  )
  assert_true(
    load_current_component_with_custody("/unused", 0L, 128)
    is Err(RefusedBeforeAcquisition(InvalidLimit)),
  )
}
