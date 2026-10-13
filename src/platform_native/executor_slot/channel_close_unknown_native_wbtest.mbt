///|
extern "C" fn channel_reuse_closed_descriptor(descriptor : Int) -> Int = "actql_executor_slot_test_reuse_closed_descriptor"

///|
fn channel_close_custody_fixture(label : String) -> (NativeExecutorSlotChild, NativeHolderChannel) {
  guard slot_test_root() is Some(root) else {
    fail("selected Channel close cases require an owned isolated executor-slot Root")
    abort("missing Channel close fixture")
  }
  let path = root + "/" + label + "-" + @env.now().to_string() + ".lock"
  let slot = open_native_executor_slot(path).unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = slot.spawn_holder_with_channel("/bin/sh", ["-c", "exit 0"]).unwrap()
  assert_eq(original.0.wait(true).unwrap(), Some(Exited(0)))
  original
}

///|
fn check_channel_close_unknown_reuse(inspection : Bool) -> Unit {
  let (child, channel) = channel_close_custody_fixture(
    if inspection { "inspection-close-unknown" } else { "writer-close-unknown" },
  )
  let original = if inspection { channel.inspection_descriptor } else { channel.descriptor }
  // Fixture consumption without its observation. The real Owner subsequently
  // receives EBADF; this is not an actual observed kernel EINTR/EIO failure.
  assert_eq(slot_close_ffi(original), 0)
  assert_false(channel.close())
  assert_true(channel.close_unknown)
  assert_eq(channel.descriptor, -1)
  assert_eq(channel.inspection_descriptor, -1)
  let new_reader = channel_reuse_closed_descriptor(original)
  assert_true(new_reader >= 0)
  assert_false(channel.close())
  assert_false(channel.close())
  assert_false(channel.send("release"))
  let independent = @utf8.encode("independent-new-pipe\n")
  // Repeated original cleanup must not close the independent reused number.
  assert_eq(channel_write_ffi(original, new_reader, independent, independent.length(), 0), independent.length())
  assert_eq(child.wait(false).unwrap(), Some(Exited(0)))
  assert_true(channel.close_unknown)
  assert_eq(slot_close_ffi(original), 0)
  assert_eq(slot_close_ffi(new_reader), 0)
}

///|
test "Channel writer close Unknown never closes an independent reused descriptor" {
  check_channel_close_unknown_reuse(false)
}

///|
test "Channel inspection close Unknown never closes an independent reused descriptor" {
  check_channel_close_unknown_reuse(true)
}

///|
test "confirmed Channel descriptor close stays idempotent without changing child observation" {
  let (child, channel) = channel_close_custody_fixture("confirmed-channel-close")
  assert_true(channel.close())
  assert_true(channel.close())
  assert_false(channel.close_unknown)
  assert_false(channel.send("release"))
  assert_eq(child.wait(false).unwrap(), Some(Exited(0)))
}
