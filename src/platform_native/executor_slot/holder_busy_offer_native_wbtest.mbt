///|
test "holder channel preserves a busy original Current before later review ticks" {
  guard slot_test_root() is Some(root) else {
    fail(
      "busy Current counter requires the original isolated executor-slot fixture",
    )
  }
  let path = root + "/busy-current.lock"
  let gate_path = root + "/busy-current-finish.lock"
  let slot = open_native_executor_slot(path).unwrap()
  assert_true(slot.try_acquire().unwrap())
  // The child holds its original Slot/stdin but cannot consume a frame until
  // the parent opens the gate. This avoids a timing-dependent busy assertion.
  let (child, channel) = slot
    .spawn_holder_with_channel("/bin/sh", [
      "-c", "while [ ! -f \"$1\" ]; do sleep 0.01; done", "holder-busy-current",
      gate_path,
    ])
    .unwrap()
  let primary = try {
    assert_true(channel.send("effect-review original-tick"))
    assert_false(channel.send("current original-request"))
    let (selected, bytes) = channel.pending_frame.unwrap()
    assert_eq(selected, "current original-request")
    assert_eq(bytes, @utf8.encode("current original-request\n"))
    assert_eq(channel.offset, 0)
    assert_false(channel.send("effect-review later-tick"))
    assert_eq(channel.pending_frame.unwrap().0, selected)
    assert_eq(
      duplex_test_read_ffi(channel.inspection_descriptor),
      @utf8.encode("effect-review original-tick\n"),
    )
    // A later offer advances the retained Current, never interleaves the tick
    // or returns a relay ACK for that different offered frame.
    assert_false(channel.send("effect-review later-tick"))
    assert_true(channel.pending_frame is None)
    assert_eq(
      duplex_test_read_ffi(channel.inspection_descriptor),
      @utf8.encode("current original-request\n"),
    )
    assert_true(channel.send("effect-review later-tick"))
    assert_eq(
      duplex_test_read_ffi(channel.inspection_descriptor),
      @utf8.encode("effect-review later-tick\n"),
    )
    None
  } catch {
    issue => Some(issue)
  }
  // Complete the same original child/FD cleanup on the red path too. Neither
  // a busy response nor the successful send above proves process retirement.
  let gate = open_native_executor_slot(gate_path).unwrap()
  assert_true(gate.close())
  assert_eq(child.wait(true).unwrap(), Some(Exited(0)))
  assert_true(channel.close())
  assert_true(slot_becomes_free(path))
  println("busy Current counter: original child/Channel/Slot cleanup confirmed")
  match primary {
    Some(issue) => raise issue
    None => ()
  }
}
