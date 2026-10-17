///|
#borrow(path, contents)
extern "C" fn selected_test_backing_ffi(
  path : Bytes,
  path_length : Int,
  contents : Bytes,
  content_length : Int,
) -> Int = "actql_executor_slot_test_selected_backing"

///|
#borrow(record)
extern "C" fn selected_test_descriptor_ffi(
  record : NativeScopedChildDescriptor,
) -> Int = "actql_executor_slot_test_selected_descriptor"

///|
extern "C" fn selected_test_no_cloexec_ffi(descriptor : Int) -> Int = "actql_executor_slot_test_selected_without_cloexec"

///|
#borrow(record)
extern "C" fn selected_test_thread_ffi(
  record : NativeScopedChildDescriptor,
) -> Int = "actql_executor_slot_test_selected_foreign_thread"

///|
fn selected_test_backing(label : String, contents : String) -> Int raise {
  let path = @utf8.encode(scoped_test_root() + "/selected-" + label + ".data")
  let bytes = @utf8.encode(contents)
  let descriptor = selected_test_backing_ffi(
    path,
    path.length(),
    bytes,
    bytes.length(),
  )
  assert_true(descriptor >= 0)
  descriptor
}

///|
fn selected_test_output(
  holder : NativeScopedExecutorHolder,
  borrowed : NativeScopedDuplexBorrow,
) -> Bytes raise {
  let (_, reader) = scoped_test_ok(
    borrowed.parent_descriptors(holder),
    "selected.output.descriptors",
  )
  let child = scoped_test_ok(holder.child(), "selected.output.child")
  let result : Array[Byte] = []
  for _ in 0..<1000 {
    for byte in duplex_test_read_ffi(reader) {
      result.push(byte)
    }
    assert_true(result.length() <= 20000)
    match scoped_test_ok(child.wait(false), "selected.output.wait") {
      Some(exit) => {
        assert_eq(exit, Exited(0))
        for _ in 0..<8 {
          let remaining = duplex_test_read_ffi(reader)
          if remaining.length() == 0 {
            return Bytes::from_array(result)
          }
          for byte in remaining {
            result.push(byte)
          }
          assert_true(result.length() <= 20000)
        }
        fail("selected output exceeded the finite fixture drain")
        abort("unreachable selected output drain failure")
      }
      None => native_wait_milliseconds(5)
    }
  }
  fail("selected child did not exit within the finite fixture")
  abort("unreachable selected child wait failure")
}

///|
fn selected_test_finish(
  slot : NativeExecutorSlot,
  holder : NativeScopedExecutorHolder,
  borrowed : NativeScopedDuplexBorrow,
  source : Int,
) -> Unit raise {
  assert_eq(duplex_test_open_ffi(source), 1)
  scoped_test_ok(borrowed.return_transport(holder), "selected.return")
  duplex_test_finish(slot, holder)
  assert_eq(duplex_test_open_ffi(source), 1)
  assert_eq(slot_close_ffi(source), 0)
}

///|
test "selected child FD4 reads the original unlinked backing without a path reopen" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-fd4")
  let source = selected_test_backing("fd4", "original-backing-bytes")
  scoped_test_ok(
    holder.prepare_duplex_child(
      "/bin/sh",
      ["-c", "exec /bin/cat <&4"],
      source,
      [],
    ),
    "selected.fd4.prepare",
  )
  assert_true(
    holder.spawn_duplex("/bin/sh", ["-c", "exit 0"])
    is Err(InvalidConfiguration),
  )
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.fd4.spawn")
  assert_eq(
    selected_test_output(holder, borrowed),
    @utf8.encode("original-backing-bytes"),
  )
  assert_true(holder.spawn_prepared_duplex() is Err(Closed))
  selected_test_finish(slot, holder, borrowed, source)
}

///|
test "selected environment retains exactly four original OS fields without ambient merging" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-env")
  let source = selected_test_backing("env", "unused-original")
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, [
      ("LANG", "C"),
      ("LC_ALL", ""),
      ("LC_CTYPE", "C"),
      ("TMPDIR", "/selected/tmp"),
    ]),
    "selected.env.prepare",
  )
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.env.spawn")
  assert_eq(
    selected_test_output(holder, borrowed),
    @utf8.encode("LANG=C\nLC_ALL=\nLC_CTYPE=C\nTMPDIR=/selected/tmp\n"),
  )
  selected_test_finish(slot, holder, borrowed, source)
}

///|
test "explicit empty selected environment remains empty in the actual child" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-empty-env")
  let source = selected_test_backing("empty-env", "unused-original")
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, []),
    "selected.empty.prepare",
  )
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.empty.spawn")
  assert_eq(selected_test_output(holder, borrowed), b"")
  selected_test_finish(slot, holder, borrowed, source)
}

///|
test "selected launch snapshots original arguments and environment before caller mutation" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-snapshot")
  let source = selected_test_backing("snapshot", "unused-original")
  let arguments = ["-c", "printf '%s' \"$LANG:original-argument\""]
  let environment = [("LANG", "original-language")]
  scoped_test_ok(
    holder.prepare_duplex_child("/bin/sh", arguments, source, environment),
    "selected.snapshot.prepare",
  )
  arguments[1] = "printf '%s' replacement-argument"
  environment[0] = ("LANG", "replacement-language")
  assert_true(
    holder.prepare_duplex_child("/usr/bin/env", [], source, [])
    is Err(InvalidConfiguration),
  )
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.snapshot.spawn")
  assert_eq(
    selected_test_output(holder, borrowed),
    @utf8.encode("original-language:original-argument"),
  )
  selected_test_finish(slot, holder, borrowed, source)
}

///|
test "selected environment refuses unknown duplicate NUL and over-limit inputs before capture" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-bounds")
  let source = selected_test_backing("bounds", "unused-original")
  let encoded : Array[Byte] = []
  for _ in 0..<2048 {
    encoded.push(0xC3)
    encoded.push(0xA9)
  }
  let exact = @utf8.decode_lossy(Bytes::from_array(encoded))
  for
    environment in [
      [("PATH", "/unselected")],
      [("LANG", "a"), ("LANG", "b")],
      [("LANG", "contains\u{0}nul")],
      [("LANG", exact + "x")],
      [
        ("LANG", "a"),
        ("LC_ALL", "b"),
        ("LC_CTYPE", "c"),
        ("TMPDIR", "d"),
        ("LANG", "e"),
      ],
    ] {
    assert_true(
      holder.prepare_duplex_child("/usr/bin/env", [], source, environment)
      is Err(InvalidConfiguration),
    )
    assert_true(holder.child_launch is None)
  }
  assert_true(
    holder.prepare_duplex_child("relative", [], source, [])
    is Err(InvalidConfiguration),
  )
  assert_true(
    holder.prepare_duplex_child("/usr/bin/env", ["arg\u{0}nul"], source, [])
    is Err(InvalidConfiguration),
  )
  assert_true(
    holder.prepare_duplex_child("/usr/bin/env", [], slot.descriptor, [])
    is Err(InvalidConfiguration),
  )
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, [("LANG", exact)]),
    "selected.bounds.prepare",
  )
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.bounds.spawn")
  assert_eq(
    selected_test_output(holder, borrowed),
    @utf8.encode("LANG=" + exact + "\n"),
  )
  selected_test_finish(slot, holder, borrowed, source)
}

///|
test "changed original source descriptor refuses launch without closing its independent replacement" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-source-reuse")
  let source = selected_test_backing("source-reuse", "original-only")
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, []),
    "selected.reuse.prepare",
  )
  assert_eq(slot_close_ffi(source), 0)
  let independent_reader = channel_reuse_closed_descriptor(source)
  assert_true(independent_reader >= 0)
  assert_true(holder.spawn_prepared_duplex() is Err(LockFailed))
  assert_false(holder.attempted)
  assert_true(holder.child() is Err(InvalidConfiguration))
  scoped_test_ok(borrowed.return_transport(holder), "selected.reuse.return")
  scoped_test_ok(holder.prepare_unstarted_cleanup(), "selected.reuse.cleanup")
  assert_true(holder.cleanup())
  let payload = @utf8.encode("independent-source-replacement")
  assert_eq(
    duplex_test_write_ffi(source, payload, payload.length()),
    payload.length(),
  )
  assert_eq(duplex_test_read_ffi(independent_reader), payload)
  assert_eq(slot_close_ffi(source), 0)
  assert_eq(slot_close_ffi(independent_reader), 0)
  assert_true(slot.close())
}

///|
test "selected duplicate close Unknown remains in its original Holder and never closes a reused FD" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare(
    "selected-copy-unknown",
  )
  let source = selected_test_backing("copy-unknown", "original-only")
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, []),
    "selected.unknown.prepare",
  )
  let duplicate = selected_test_descriptor_ffi(
    holder.child_launch.unwrap().resource,
  )
  assert_eq(slot_close_ffi(duplicate), 0)
  let independent_reader = channel_reuse_closed_descriptor(duplicate)
  assert_true(independent_reader >= 0)
  assert_true(holder.spawn_prepared_duplex() is Err(LockFailed))
  scoped_test_ok(borrowed.return_transport(holder), "selected.unknown.return")
  assert_true(holder.prepare_unstarted_cleanup() is Err(LockFailed))
  assert_eq(duplex_closed_ffi(transport.resource), 0)
  assert_false(holder.cleanup())
  let payload = @utf8.encode("independent-duplicate-replacement")
  assert_eq(
    duplex_test_write_ffi(duplicate, payload, payload.length()),
    payload.length(),
  )
  assert_eq(duplex_test_read_ffi(independent_reader), payload)
  assert_eq(slot_close_ffi(duplicate), 0)
  assert_eq(slot_close_ffi(independent_reader), 0)
  assert_eq(slot_close_ffi(source), 0)
  assert_true(slot.close())
  scoped_test_pending.push(holder)
}

///|
test "non-CLOEXEC original backing capture refuses and retains finite preparation for cleanup" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-cloexec")
  let source = selected_test_backing("cloexec", "original-only")
  assert_eq(selected_test_no_cloexec_ffi(source), 0)
  assert_true(
    holder.prepare_duplex_child("/usr/bin/env", [], source, [])
    is Err(OpenFailed),
  )
  assert_true(holder.child_launch is Some(_))
  assert_true(
    holder.prepare_duplex_child("/usr/bin/env", [], source, [])
    is Err(InvalidConfiguration),
  )
  assert_true(
    holder.spawn_duplex("/bin/sh", ["-c", "exit 0"])
    is Err(InvalidConfiguration),
  )
  assert_true(holder.child() is Err(InvalidConfiguration))
  scoped_test_ok(borrowed.return_transport(holder), "selected.cloexec.return")
  scoped_test_ok(holder.prepare_unstarted_cleanup(), "selected.cloexec.cleanup")
  assert_true(holder.cleanup())
  assert_eq(duplex_test_open_ffi(source), 1)
  assert_eq(slot_close_ffi(source), 0)
  assert_true(slot.close())
}

///|
test "selected launch refusal preserves one attempt and the original backing source" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-refused")
  let source = selected_test_backing("refused", "original-only")
  scoped_test_ok(
    holder.prepare_duplex_child("/actql-no-such-selected-child", [], source, []),
    "selected.refused.prepare",
  )
  assert_true(holder.spawn_prepared_duplex() is Err(SpawnFailed))
  assert_true(holder.duplex_spawn_returned)
  assert_true(holder.spawn_prepared_duplex() is Err(Closed))
  assert_true(holder.child() is Err(InvalidConfiguration))
  scoped_test_ok(borrowed.return_transport(holder), "selected.refused.return")
  scoped_test_ok(holder.prepare_unstarted_cleanup(), "selected.refused.cleanup")
  assert_true(holder.cleanup())
  assert_eq(duplex_test_open_ffi(source), 1)
  assert_eq(slot_close_ffi(source), 0)
  assert_true(slot.close())
}

///|
test "selected launch cannot replace a lost original slot and still permits no-child withdrawal" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-replaced")
  let source = selected_test_backing("replaced", "original-only")
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, []),
    "selected.replaced.prepare",
  )
  let path = @utf8.encode(slot.path)
  assert_eq(scoped_test_replace_slot(path, path.length()), 0)
  assert_true(holder.spawn_prepared_duplex() is Err(Replaced))
  scoped_test_ok(borrowed.return_transport(holder), "selected.replaced.return")
  scoped_test_ok(
    holder.prepare_unstarted_cleanup(),
    "selected.replaced.cleanup",
  )
  assert_true(holder.cleanup())
  assert_eq(slot_close_ffi(source), 0)
  assert_true(slot.close())
}

///|
test "selected backing descriptor currentness stays on the original control thread" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-thread")
  let source = selected_test_backing("thread", "unused-original")
  scoped_test_ok(
    holder.prepare_duplex_child("/usr/bin/env", [], source, []),
    "selected.thread.prepare",
  )
  let record = holder.child_launch.unwrap().resource
  assert_eq(selected_test_thread_ffi(record), -1)
  assert_eq(selected_child_current_ffi(record), 0)
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.thread.spawn")
  assert_eq(selected_test_output(holder, borrowed), b"")
  selected_test_finish(slot, holder, borrowed, source)
}

///|
test "selected arguments preserve the exact original 255 bound and reject one extra" {
  let (slot, holder, _, borrowed) = duplex_test_prepare("selected-argv-limit")
  let source = selected_test_backing("argv-limit", "unused-original")
  let arguments = ["-c", "printf '%s' \"$#\"", "original-zero"]
  for _ in 0..<252 {
    arguments.push("original-argument")
  }
  assert_eq(arguments.length(), 255)
  let excessive = [..arguments, "one-extra"]
  assert_true(
    holder.prepare_duplex_child("/bin/sh", excessive, source, [])
    is Err(InvalidConfiguration),
  )
  assert_true(holder.child_launch is None)
  scoped_test_ok(
    holder.prepare_duplex_child("/bin/sh", arguments, source, []),
    "selected.argv.prepare",
  )
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.argv.spawn")
  assert_eq(selected_test_output(holder, borrowed), @utf8.encode("252"))
  selected_test_finish(slot, holder, borrowed, source)
}

///|
fn selected_test_refused_spawn(
  holder : NativeScopedExecutorHolder,
  result : Int,
) -> Unit raise {
  if result > 0 {
    // Even a failing ABI counter retains any actual original child before
    // its assertion. No unexpected PID is discarded or called not-started.
    holder.attempted = true
    ignore(holder.original.record_spawn_result(result, Some(holder)))
    holder.duplex_spawn_returned = true
    scoped_test_pending.push(holder)
    fail("invalid selected physical call unexpectedly started a child")
    abort("unreachable unexpected selected child")
  }
  assert_eq(result, -1)
}

///|
test "actual selected C boundary refuses FD role swaps length overflow and unselected env" {
  let (slot, holder, transport, borrowed) = duplex_test_prepare("selected-abi")
  let source = selected_test_backing("abi", "unused-original")
  scoped_test_ok(
    holder.prepare_duplex_child("/bin/sh", ["-c", "exit 0"], source, []),
    "selected.abi.prepare",
  )
  let launch = holder.child_launch.unwrap()
  let input = duplex_descriptor_ffi(transport.resource, 0)
  let output = duplex_descriptor_ffi(transport.resource, 2)
  let empty = b""
  for
    (
      target,
      input_fd,
      output_fd,
      executable_length,
      argument_length,
      environment,
      environment_length,
    ) in [
      (
        4,
        input,
        output,
        launch.executable.length(),
        launch.arguments.length(),
        empty,
        0,
      ),
      (
        3,
        output,
        input,
        launch.executable.length(),
        launch.arguments.length(),
        empty,
        0,
      ),
      (
        3,
        input,
        output,
        launch.executable.length() + 1,
        launch.arguments.length(),
        empty,
        0,
      ),
      (
        3,
        input,
        output,
        launch.executable.length() - 1,
        launch.arguments.length(),
        empty,
        0,
      ),
      (
        3,
        input,
        output,
        launch.executable.length(),
        launch.arguments.length() + 1,
        empty,
        0,
      ),
      (
        3,
        input,
        output,
        launch.executable.length(),
        launch.arguments.length(),
        empty,
        1,
      ),
      (
        3,
        input,
        output,
        launch.executable.length(),
        launch.arguments.length(),
        b"PATH=/unselected\x00",
        17,
      ),
      (
        3,
        input,
        output,
        launch.executable.length(),
        launch.arguments.length(),
        b"LANG=a\x00LANG=b\x00",
        14,
      ),
      (
        3,
        input,
        output,
        launch.executable.length(),
        launch.arguments.length(),
        b"LANG=a\x00unselected-trailing",
        7,
      ),
    ] {
    let result = spawn_selected_duplex_ffi(
      launch.executable,
      executable_length,
      launch.arguments,
      argument_length,
      slot.descriptor,
      target,
      input_fd,
      output_fd,
      launch.resource,
      environment,
      environment_length,
    )
    selected_test_refused_spawn(holder, result)
    assert_true(holder.child() is Err(InvalidConfiguration))
    assert_false(holder.attempted)
  }
  // Refusal did not consume or replace the one prepared original selection.
  scoped_test_ok(holder.spawn_prepared_duplex(), "selected.abi.original-spawn")
  assert_eq(selected_test_output(holder, borrowed), b"")
  selected_test_finish(slot, holder, borrowed, source)
}
