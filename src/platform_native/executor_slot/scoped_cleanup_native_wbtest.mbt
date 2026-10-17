///|
test "unstarted cleanup retains the original anchor and does not authorize a launch" {
  let (slot, holder) = scoped_test_ready("cleanup-prepared")
  scoped_test_ok(holder.prepare_unstarted_cleanup(), "cleanup.prepared")
  assert_false(holder.closed)
  assert_eq(scoped_anchor_status_ffi(holder.anchor), 0)
  assert_true(holder.require_prepared() is Ok(_))
  assert_true(holder.child() is Err(InvalidConfiguration))
  assert_true(holder.cleanup())
  assert_true(holder.prepare_unstarted_cleanup() is Err(Closed))
  assert_true(slot.close())
}

///|
test "known refused duplex spawn can retire transport without reopening its one attempt" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare(
    "cleanup-refused",
  )
  assert_true(
    holder.spawn_duplex("/actql-no-such-cleanup-executable", [])
    is Err(SpawnFailed),
  )
  assert_true(holder.duplex_spawn_returned)
  assert_true(holder.prepare_unstarted_cleanup() is Err(Busy))
  scoped_test_ok(borrowed.return_transport(holder), "cleanup.return")
  scoped_test_ok(holder.prepare_unstarted_cleanup(), "cleanup.refused")
  assert_eq(duplex_closed_ffi(transport.resource), 0)
  assert_false(holder.closed)
  assert_true(holder.require_prepared() is Err(Closed))
  assert_true(holder.spawn_duplex("/bin/sh", ["-c", "exit 0"]) is Err(Closed))
  assert_true(holder.child() is Err(InvalidConfiguration))
  assert_true(holder.poll_stop() is Err(InvalidConfiguration))
  assert_true(holder.cleanup())
  assert_true(slot.close())
}

///|
test "actual child remains outside unstarted cleanup after its wait observation" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("cleanup-started")
  scoped_test_ok(holder.spawn_duplex("/bin/sh", ["-c", "exit 0"]), "cleanup.spawn")
  scoped_test_ok(borrowed.return_transport(holder), "cleanup.started.return")
  let child = scoped_test_ok(holder.child(), "cleanup.child")
  assert_eq(scoped_test_ok(child.wait(true), "cleanup.wait"), Some(Exited(0)))
  assert_true(holder.prepare_unstarted_cleanup() is Err(Busy))
  duplex_test_finish(slot, holder)
  assert_true(holder.prepare_unstarted_cleanup() is Err(Busy))
}

///|
test "unresolved original duplex attempt cannot acknowledge no child or transport cleanup" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("cleanup-unresolved")
  scoped_test_ok(borrowed.return_transport(holder), "cleanup.unresolved.return")
  // Finite state counter: model interruption before the synchronous launch
  // returns. No PID absence or external error may fill that observation.
  holder.attempted = true
  assert_false(holder.duplex_spawn_returned)
  assert_true(holder.prepare_unstarted_cleanup() is Err(Busy))
  assert_false(holder.cleanup())
  assert_false(holder.closed)
  assert_true(slot.is_open())
  scoped_test_pending.push(holder)
}

///|
test "unstarted cleanup preserves an actual consumed-descriptor Unknown and independent reuse" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("cleanup-unknown")
  let (writer, _) = scoped_test_ok(
    borrowed.parent_descriptors(holder),
    "cleanup.unknown.descriptors",
  )
  assert_eq(slot_close_ffi(writer), 0)
  assert_true(borrowed.require_current(holder) is Err(LockFailed))
  let independent_reader = channel_reuse_closed_descriptor(writer)
  assert_true(independent_reader >= 0)
  scoped_test_ok(borrowed.return_transport(holder), "cleanup.unknown.return")
  assert_true(holder.prepare_unstarted_cleanup() is Err(LockFailed))
  assert_false(holder.cleanup())
  let payload = @utf8.encode("same-independent-reuse")
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
test "known unstarted cleanup can withdraw transport after original pathname replacement" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare(
    "cleanup-replaced",
  )
  let path = @utf8.encode(slot.path)
  assert_eq(scoped_test_replace_slot(path, path.length()), 0)
  assert_true(borrowed.require_current(holder) is Err(Replaced))
  scoped_test_ok(borrowed.return_transport(holder), "cleanup.replaced.return")
  scoped_test_ok(holder.prepare_unstarted_cleanup(), "cleanup.replaced")
  assert_eq(duplex_closed_ffi(transport.resource), 0)
  assert_false(holder.closed)
  assert_true(holder.cleanup())
  assert_true(slot.close())
}

///|
test "old attempted one-way path does not gain a new no-child acknowledgement" {
  let (slot, holder) = scoped_test_ready("cleanup-one-way")
  assert_true(
    holder.spawn_with_channel("/actql-no-such-one-way-executable", [])
    is Err(SpawnFailed),
  )
  assert_true(holder.prepare_unstarted_cleanup() is Err(Busy))
  assert_true(holder.require_prepared() is Err(Closed))
  assert_true(holder.child() is Err(InvalidConfiguration))
  assert_true(holder.cleanup())
  assert_true(slot.close())
}
