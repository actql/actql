///|
fn[T] scoped_test_ok(
  result : Result[T, NativeExecutorSlotIssue],
  phase : String,
) -> T raise {
  match result {
    Ok(value) => value
    Err(_) => {
      fail(phase)
      abort("unreachable scoped fixture failure")
    }
  }
}

///|
fn scoped_test_root() -> String raise {
  match slot_test_root() {
    Some(root) => root
    None => {
      fail("scoped stop requires its selected fresh executor-slot Root")
      abort("unreachable missing fixture Root")
    }
  }
}

///|
fn scoped_test_ready(
  label : String,
) -> (NativeExecutorSlot, NativeScopedExecutorHolder) raise {
  let slot = scoped_test_ok(
    open_native_executor_slot(scoped_test_root() + "/scoped-" + label + ".lock"),
    "slot.open",
  )
  assert_true(scoped_test_ok(slot.try_acquire(), "slot.acquire"))
  match slot.prepare_scoped_holder() {
    Ready(holder) => (slot, holder)
    Refused(holder, _) => {
      ignore(holder.cleanup())
      ignore(slot.close())
      fail("scope.prepare")
      abort("unreachable refused scoped fixture")
    }
  }
}

///|
fn scoped_test_stop(
  holder : NativeScopedExecutorHolder,
) -> NativeScopedExecutorStop raise {
  for _ in 0..<1000 {
    match scoped_test_ok(holder.poll_stop(), "scope.poll_stop") {
      Some(stop) => return stop
      None => native_wait_milliseconds(5)
    }
  }
  fail("scope stop did not arrive inside the bounded fixture")
  abort("unreachable missing stop")
}

///|
// Deliberate negative carriers stay owned through this probe's process exit.
// Process exit is not reported as a successful component cleanup ACK.
let scoped_test_pending : Array[NativeScopedExecutorHolder] = []

///|
#borrow(anchor)
extern "C" fn scoped_test_foreign_thread(
  anchor : NativeExecutorSlotAnchor,
) -> Int = "actql_executor_slot_test_anchor_foreign_thread"

///|
test "scoped anchor rejects a foreign thread without changing original preparation" {
  let (slot, holder) = scoped_test_ready("thread")
  assert_eq(scoped_test_foreign_thread(holder.anchor), 1)
  scoped_test_ok(holder.require_prepared(), "thread.original-current")
  assert_true(holder.cleanup())
  assert_true(slot.close())
}

///|
test "scoped preparation refuses an unheld original and keeps partial cleanup explicit" {
  let slot = scoped_test_ok(
    open_native_executor_slot(scoped_test_root() + "/scoped-unheld.lock"),
    "unheld.open",
  )
  match slot.prepare_scoped_holder() {
    Refused(holder, issue) => {
      assert_eq(issue, NotHeld)
      assert_true(holder.require_prepared() is Err(NotHeld))
      assert_true(holder.child() is Err(InvalidConfiguration))
      assert_true(holder.cleanup())
      assert_true(slot.is_open())
    }
    Ready(_) => fail("unheld slot issued a prepared holder")
  }
  assert_true(slot.close())
}

///|
test "scoped stop needs actual child exit and retains its slot pin until explicit close" {
  let (slot, holder) = scoped_test_ready("pin")
  scoped_test_ok(holder.require_prepared(), "prepared.current")
  scoped_test_ok(
    holder.spawn_with_channel("/bin/sh", ["-c", "read token; exit 0"]),
    "spawn",
  )
  assert_true(holder.require_prepared() is Err(Closed))
  assert_true(holder.poll_stop() is Ok(None))
  assert_false(holder.cleanup())
  let channel = scoped_test_ok(holder.channel(), "channel")
  assert_true(channel.send("finish"))
  let child = scoped_test_ok(holder.child(), "child")
  assert_eq(scoped_test_ok(child.wait(true), "child.wait"), Some(Exited(0)))
  let stop = scoped_test_stop(holder)
  scoped_test_ok(stop.require_current(holder), "stop.current")
  let probe = scoped_test_ok(open_native_executor_slot(slot.path), "probe.open")
  assert_false(scoped_test_ok(probe.try_acquire(), "probe.busy"))
  assert_false(holder.cleanup())
  let repeated = scoped_test_stop(holder)
  assert_true(physical_equal(stop, repeated))
  assert_true(stop.close())
  assert_true(stop.close())
  assert_true(holder.cleanup())
  assert_true(stop.require_current(holder) is Err(Closed))
  assert_true(scoped_test_ok(probe.try_acquire(), "probe.free"))
  assert_true(probe.close())
}

///|
test "scoped spawn refusal does not issue a stop or a second attempt" {
  let (slot, holder) = scoped_test_ready("spawn-refused")
  assert_true(
    holder.spawn_with_channel(scoped_test_root() + "/missing-executable", [])
    is Err(SpawnFailed),
  )
  assert_true(holder.require_prepared() is Err(Closed))
  assert_true(holder.poll_stop() is Err(InvalidConfiguration))
  assert_true(
    holder.spawn_with_channel("/bin/sh", ["-c", "exit 0"]) is Err(Closed),
  )
  assert_true(holder.cleanup())
  scoped_test_ok(slot.verify_current_hold(), "original.still-held")
  assert_true(slot.close())
}

///|
test "scoped wait of the holder cannot retire a still-held descendant slot" {
  let (_, holder) = scoped_test_ready("descendant")
  let release = scoped_test_root() + "/scoped-descendant-release"
  scoped_test_ok(
    holder.spawn_with_channel("/bin/sh", [
      "-c", "/bin/sh -c 'while [ ! -f \"$1\" ]; do /bin/sleep 0.01; done' descendant \"$1\" & exit 0",
      "holder", release,
    ]),
    "descendant.spawn",
  )
  let child = scoped_test_ok(holder.child(), "descendant.child")
  assert_eq(
    scoped_test_ok(child.wait(true), "descendant.wait-holder"),
    Some(Exited(0)),
  )
  assert_true(holder.poll_stop() is Ok(None))
  assert_false(holder.cleanup())
  assert_true(native_append_evidence_line(release, "release"))
  let stop = scoped_test_stop(holder)
  scoped_test_ok(stop.require_current(holder), "descendant.stop")
  assert_true(stop.close())
  assert_true(holder.cleanup())
}

///|
test "scoped stop rejects another holder even after both actual children exit" {
  let (_, first) = scoped_test_ready("foreign-first")
  let (_, second) = scoped_test_ready("foreign-second")
  scoped_test_ok(
    first.spawn_with_channel("/bin/sh", ["-c", "exit 0"]),
    "first.spawn",
  )
  scoped_test_ok(
    second.spawn_with_channel("/bin/sh", ["-c", "exit 0"]),
    "second.spawn",
  )
  scoped_test_ok(
    scoped_test_ok(first.child(), "first.child").wait(true),
    "first.wait",
  )
  |> ignore
  scoped_test_ok(
    scoped_test_ok(second.child(), "second.child").wait(true),
    "second.wait",
  )
  |> ignore
  let a = scoped_test_stop(first)
  let b = scoped_test_stop(second)
  assert_true(a.require_current(second) is Err(NotHeld))
  assert_true(b.require_current(first) is Err(NotHeld))
  scoped_test_ok(a.require_current(first), "first.current")
  scoped_test_ok(b.require_current(second), "second.current")
  assert_true(a.close())
  assert_true(b.close())
  assert_true(first.cleanup())
  assert_true(second.cleanup())
}

///|
#borrow(path)
extern "C" fn scoped_test_replace_slot(path : Bytes, length : Int) -> Int = "actql_executor_slot_test_replace_scoped_slot"

///|
test "scoped stop refuses a replaced slot pathname without rebinding the original" {
  let (slot, holder) = scoped_test_ready("replaced")
  scoped_test_ok(
    holder.spawn_with_channel("/bin/sh", ["-c", "exit 0"]),
    "replace.spawn",
  )
  scoped_test_ok(
    scoped_test_ok(holder.child(), "replace.child").wait(true),
    "replace.wait",
  )
  |> ignore
  let path = @utf8.encode(slot.path)
  assert_eq(scoped_test_replace_slot(path, path.length()), 0)
  assert_true(holder.poll_stop() is Err(Replaced))
  assert_true(holder.poll_stop() is Err(Replaced))
  assert_false(holder.cleanup())
  scoped_test_pending.push(holder)
}

///|
test "scoped stop preserves the original Channel close Unknown" {
  let (_, holder) = scoped_test_ready("channel-unknown")
  scoped_test_ok(
    holder.spawn_with_channel("/bin/sh", ["-c", "exit 0"]),
    "unknown.spawn",
  )
  scoped_test_ok(
    scoped_test_ok(holder.child(), "unknown.child").wait(true),
    "unknown.wait",
  )
  |> ignore
  let channel = scoped_test_ok(holder.channel(), "unknown.channel")
  assert_eq(slot_close_ffi(channel.descriptor), 0)
  assert_true(holder.poll_stop() is Err(LockFailed))
  assert_true(channel.close_unknown)
  assert_true(holder.poll_stop() is Err(LockFailed))
  assert_false(holder.cleanup())
  scoped_test_pending.push(holder)
}

///|
#borrow(anchor)
extern "C" fn scoped_test_anchor_descriptor(
  anchor : NativeExecutorSlotAnchor,
) -> Int = "actql_executor_slot_test_anchor_descriptor"

///|
test "scoped stop close Unknown cannot close an independent reused descriptor" {
  let (_, holder) = scoped_test_ready("close-unknown")
  scoped_test_ok(
    holder.spawn_with_channel("/bin/sh", ["-c", "exit 0"]),
    "close.spawn",
  )
  scoped_test_ok(
    scoped_test_ok(holder.child(), "close.child").wait(true),
    "close.wait",
  )
  |> ignore
  let stop = scoped_test_stop(holder)
  let original = scoped_test_anchor_descriptor(stop.anchor)
  assert_eq(slot_close_ffi(original), 0)
  assert_false(stop.close())
  let reader = channel_reuse_closed_descriptor(original)
  assert_true(reader >= 0)
  assert_false(stop.close())
  assert_false(holder.cleanup())
  assert_true(stop.require_current(holder) is Err(Closed))
  let body = b"independent scoped-close probe\n"
  assert_eq(
    channel_write_ffi(original, reader, body, body.length(), 0),
    body.length(),
  )
  assert_eq(slot_close_ffi(original), 0)
  assert_eq(slot_close_ffi(reader), 0)
  scoped_test_pending.push(holder)
}
