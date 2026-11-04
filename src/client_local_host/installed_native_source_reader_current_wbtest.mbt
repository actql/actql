///|
fn current_native_reader_limits() -> Array[Int] {
  [
    4000000, 48000000, 400000, 32, 2000, 100, 12, 2000, 2048, 4000000, 24002944,
    400000, 4000000, 4000000, 400000, 32,
  ]
}

///|
test "native reader funds received raw prefix and only one next response" {
  let limits = current_native_reader_limits()
  let native = @execution.execution_capacity(7L, 9L)
  let initial = installed_native_source_reader_capacity(
    limits,
    100,
    65536,
    native,
    received=Some((0L, 0)),
  ).unwrap()
  let next = installed_native_source_reader_capacity(
    limits,
    100,
    65536,
    native,
    received=Some((557L, 1)),
  ).unwrap()
  let maximum = installed_native_source_reader_capacity(
    limits, 100, 65536, native,
  ).unwrap()
  let before = @execution.execution_capacity_retained_bytes(initial)
  let after = @execution.execution_capacity_retained_bytes(next)
  assert_true(after - before >= 557L)
  assert_true(after - before < 2048L)
  // Original 48MB future-total bound remains rejection DATA; it is not part
  // of this zero-received prefix's retained response allocation.
  assert_true(
    @execution.execution_capacity_retained_bytes(maximum) - before > 48000000L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(initial) < 100000000L,
  )
}

///|
test "native reader current raw counters retain finite original bounds" {
  let limits = current_native_reader_limits()
  let native = @execution.execution_capacity(0L, 0L)
  for current in [(-1L, 0), (0L, -1), (0L, 13), (52000001L, 12)] {
    assert_true(
      installed_native_source_reader_capacity(
        limits,
        100,
        65536,
        native,
        received=Some(current),
      )
      is None,
    )
  }
}
