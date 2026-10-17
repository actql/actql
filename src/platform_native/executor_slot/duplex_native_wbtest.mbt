///|
extern "C" fn duplex_test_partial_ffi() -> NativeScopedDuplexResource = "actql_executor_slot_test_duplex_partial"

///|
#borrow(bytes)
extern "C" fn duplex_test_write_ffi(
  descriptor : Int,
  bytes : Bytes,
  length : Int,
) -> Int = "actql_executor_slot_test_duplex_write"

///|
extern "C" fn duplex_test_read_ffi(descriptor : Int) -> Bytes = "actql_executor_slot_test_duplex_read"

///|
extern "C" fn duplex_test_open_ffi(descriptor : Int) -> Int = "actql_executor_slot_test_duplex_open_descriptor"

///|
#borrow(resource)
extern "C" fn duplex_test_thread_ffi(
  resource : NativeScopedDuplexResource,
) -> Int = "actql_executor_slot_test_duplex_foreign_thread"

///|
fn duplex_test_prepare(
  label : String,
) -> (
  NativeExecutorSlot,
  NativeScopedExecutorHolder,
  NativeScopedDuplexTransport,
  NativeScopedDuplexBorrow,
) raise {
  let (slot, holder) = scoped_test_ready("duplex-" + label)
  let transport = scoped_test_ok(holder.prepare_duplex(), "duplex.prepare")
  let borrowed = scoped_test_ok(
    transport.borrow_transport(holder),
    "duplex.borrow",
  )
  (slot, holder, transport, borrowed)
}

///|
fn duplex_test_finish(
  slot : NativeExecutorSlot,
  holder : NativeScopedExecutorHolder,
) -> Unit raise {
  let stop = scoped_test_stop(holder)
  scoped_test_ok(stop.require_current(holder), "duplex.stop.current")
  assert_true(stop.close())
  assert_true(holder.cleanup())
  assert_true(slot.close())
}

///|
test "duplex original parent descriptors carry actual child stdin and stdout" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("echo")
  let (writer, reader) = scoped_test_ok(
    borrowed.parent_descriptors(holder),
    "duplex.parent-descriptors",
  )
  let original = @utf8.encode("original-duplex-payload\n")
  // The independent write-direction refusal detects a same-Int role swap.
  assert_eq(duplex_test_write_ffi(reader, original, original.length()), -1)
  scoped_test_ok(holder.spawn_duplex("/bin/cat", []), "duplex.spawn")
  assert_eq(
    duplex_test_write_ffi(writer, original, original.length()),
    original.length(),
  )
  let observed : Array[Byte] = []
  for _ in 0..<500 {
    for byte in duplex_test_read_ffi(reader) {
      observed.push(byte)
    }
    if observed.length() >= original.length() {
      break
    }
    native_wait_milliseconds(5)
  }
  scoped_test_ok(borrowed.return_transport(holder), "duplex.return")
  duplex_test_finish(slot, holder)
  assert_eq(Bytes::from_array(observed), original)
}

///|
test "duplex active borrow prevents close and Stop even after actual child exit" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("busy")
  let descriptors = scoped_test_ok(
    borrowed.parent_descriptors(holder),
    "busy.descriptors",
  )
  scoped_test_ok(holder.spawn_duplex("/bin/sh", ["-c", "exit 0"]), "busy.spawn")
  let child = scoped_test_ok(holder.child(), "busy.child")
  assert_eq(scoped_test_ok(child.wait(true), "busy.wait"), Some(Exited(0)))
  assert_true(holder.poll_stop() is Err(Busy))
  assert_false(holder.cleanup())
  assert_eq(duplex_test_open_ffi(descriptors.0), 1)
  assert_eq(duplex_test_open_ffi(descriptors.1), 1)
  scoped_test_ok(borrowed.return_transport(holder), "busy.return")
  duplex_test_finish(slot, holder)
}

///|
test "duplex return invalidates its original view without child or loan acknowledgement" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare("return")
  scoped_test_ok(borrowed.return_transport(holder), "return.first")
  scoped_test_ok(borrowed.return_transport(holder), "return.same")
  assert_true(borrowed.parent_descriptors(holder) is Err(Closed))
  assert_true(transport.borrow_transport(holder) is Err(Busy))
  assert_true(holder.spawn_duplex("/bin/cat", []) is Err(Busy))
  assert_true(holder.child() is Err(InvalidConfiguration))
  assert_true(holder.poll_stop() is Err(InvalidConfiguration))
  assert_true(holder.cleanup())
  assert_true(slot.close())
}

///|
test "duplex foreign holder and borrow refuse before altering the original view" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare("original")
  let (other_slot, other_holder, other_transport, other_borrow) = duplex_test_prepare(
    "foreign",
  )
  assert_true(borrowed.parent_descriptors(other_holder) is Err(NotHeld))
  assert_true(borrowed.require_current(other_holder) is Err(NotHeld))
  assert_true(borrowed.return_transport(other_holder) is Err(NotHeld))
  assert_true(transport.borrow_transport(other_holder) is Err(NotHeld))
  assert_true(other_borrow.return_transport(holder) is Err(NotHeld))
  assert_true(other_transport.borrow_transport(holder) is Err(NotHeld))
  assert_true(borrowed.parent_descriptors(holder) is Ok(_))
  scoped_test_ok(borrowed.require_current(holder), "foreign.original-current")
  scoped_test_ok(borrowed.return_transport(holder), "foreign.original-return")
  scoped_test_ok(
    other_borrow.return_transport(other_holder),
    "foreign.other-return",
  )
  assert_true(holder.cleanup())
  assert_true(other_holder.cleanup())
  assert_true(slot.close())
  assert_true(other_slot.close())
}

///|
test "duplex same original partial allocation keeps known endpoints for cleanup" {
  let (slot, holder) = scoped_test_ready("duplex-partial")
  assert_true(
    holder.prepare_duplex_using(duplex_test_partial_ffi) is Err(OpenFailed),
  )
  let transport = holder.duplex.unwrap()
  assert_true(duplex_closed_ffi(transport.resource) != 0)
  assert_true(holder.prepare_duplex() is Err(InvalidConfiguration))
  assert_true(
    holder.spawn_with_channel("/bin/sh", ["-c", "exit 0"])
    is Err(InvalidConfiguration),
  )
  assert_true(holder.cleanup())
  assert_eq(duplex_closed_ffi(transport.resource), 0)
  assert_true(slot.close())
}

///|
test "duplex failed launch is one attempt with explicit original borrow cleanup" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("spawn-refused")
  assert_true(
    holder.spawn_duplex("/actql-no-such-executable", []) is Err(SpawnFailed),
  )
  assert_true(holder.spawn_duplex("/bin/sh", ["-c", "exit 0"]) is Err(Closed))
  assert_false(holder.cleanup())
  assert_true(holder.child() is Err(InvalidConfiguration))
  scoped_test_ok(borrowed.return_transport(holder), "spawn-refused.return")
  assert_true(holder.cleanup())
  assert_true(slot.close())
}

///|
test "duplex original descendant lock remains required after parent endpoints close" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("descendant")
  scoped_test_ok(
    holder.spawn_duplex("/bin/sh", ["-c", "sleep 0.2 >&2 & exit 0"]),
    "descendant.spawn",
  )
  let child = scoped_test_ok(holder.child(), "descendant.child")
  assert_eq(
    scoped_test_ok(child.wait(true), "descendant.wait"),
    Some(Exited(0)),
  )
  scoped_test_ok(borrowed.return_transport(holder), "descendant.return")
  assert_true(holder.poll_stop() is Ok(None))
  duplex_test_finish(slot, holder)
}

///|
test "duplex descriptor close Unknown cannot close an independently reused number" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("close-unknown")
  let (writer, _) = scoped_test_ok(
    borrowed.parent_descriptors(holder),
    "close-unknown.descriptors",
  )
  scoped_test_ok(
    holder.spawn_duplex("/bin/sh", ["-c", "exit 0"]),
    "close-unknown.spawn",
  )
  let child = scoped_test_ok(holder.child(), "close-unknown.child")
  assert_eq(
    scoped_test_ok(child.wait(true), "close-unknown.wait"),
    Some(Exited(0)),
  )
  // Fixture consumption without the Owner's observation, not a real kernel
  // EINTR/EIO result. Reuse is independent and must survive refused cleanup.
  assert_eq(slot_close_ffi(writer), 0)
  assert_true(borrowed.parent_descriptors(holder) is Err(LockFailed))
  let independent_reader = channel_reuse_closed_descriptor(writer)
  assert_true(independent_reader >= 0)
  assert_true(borrowed.return_transport(holder) is Err(LockFailed))
  assert_true(holder.poll_stop() is Err(Busy))
  assert_false(holder.cleanup())
  let payload = @utf8.encode("independent-reused-endpoint")
  assert_eq(
    duplex_test_write_ffi(writer, payload, payload.length()),
    payload.length(),
  )
  assert_eq(duplex_test_read_ffi(independent_reader), payload)
  assert_eq(slot_close_ffi(writer), 0)
  assert_eq(slot_close_ffi(independent_reader), 0)
  assert_true(slot.close())
  scoped_test_pending.push(holder)
}

///|
test "duplex foreign thread cannot observe endpoints and original thread remains current" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare("thread")
  assert_eq(duplex_test_thread_ffi(transport.resource), -1)
  assert_true(borrowed.parent_descriptors(holder) is Ok(_))
  scoped_test_ok(borrowed.return_transport(holder), "thread.return")
  assert_true(holder.cleanup())
  assert_true(slot.close())
}
