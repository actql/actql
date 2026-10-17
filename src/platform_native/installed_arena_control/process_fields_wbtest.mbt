///|
test "private process field transport distinguishes empty arguments and refuses incomplete or invalid UTF-8 fields" {
  assert_eq(decode_process_fields(b"", 255), Some([]))
  assert_eq(decode_process_fields(b"\x00", 255), Some([""]))
  assert_eq(decode_process_fields(b"one\x00two\x00", 255), Some(["one", "two"]))
  assert_eq(decode_process_fields(b"unterminated", 255), None)
  assert_eq(decode_process_fields(b"\xff\x00", 255), None)
  assert_eq(decode_process_fields(b"one\x00two\x00", 1), None)
  assert_eq(decode_process_fields(b"\x00", 0), None)
}

///|
test "private process bytes delegate original child snapshot and reject malformed environment before physical capture" {
  let fixture = installed_process_fixture("installed-child-byte-transport")
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  let refused = prepare_installed_arena_process_child_bytes_reply(
    fixture.host,
    fixture.domain,
    process,
    "/usr/bin/true",
    b"",
    b"LANG\x00",
  )
  assert_eq(refused.issue_family(), 9)
  assert_true(physical_equal(refused.original_process().unwrap(), process))
  process.holder.unwrap().require_prepared().unwrap()
  let ready = prepare_installed_arena_process_child_bytes_reply(
    fixture.host,
    fixture.domain,
    process,
    "/usr/bin/true",
    b"",
    b"LANG\x00C\x00",
  )
  assert_eq(ready.issue_family(), 0)
  let spawned = operate_installed_arena_process_reply(
    fixture.host,
    fixture.domain,
    process,
    11,
  )
  assert_eq(spawned.issue_family(), 0)
  assert_eq(
    process.holder.unwrap().child().unwrap().wait(true).unwrap(),
    Some(@executor.Exited(0)),
  )
  installed_child_stop_and_finish(fixture, process)
}
