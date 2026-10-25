///|
test "invalid FD typed reply keeps the same nonconsumed original intent" {
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 31),
    1L,
    64L * page_bytes_ffi(),
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 64L * page_bytes_ffi(),
    },
    65536L,
  ).unwrap()
  let refused = acquire_installed_arena_fd_reply(host, -1)
  assert_eq(refused.operation_tag(), 2)
  assert_eq(refused.issue_family(), 1)
  assert_true(
    refused.original_host() is Some(value) && physical_equal(value, host),
  )
  assert_false(host.acquisition_started)
  host.acquire().unwrap()
  host.try_close().unwrap()
}

///|
test "failed FD reply retains original partial Host and denies a second acquire" {
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 31),
    1L,
    64L * page_bytes_ffi(),
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 64L * page_bytes_ffi(),
    },
    65536L,
  ).unwrap()
  let failed = acquire_installed_arena_fd_reply(host, 2147483647)
  assert_eq(failed.operation_tag(), 2)
  assert_eq(failed.issue_family(), 6)
  assert_true(
    failed.original_host() is Some(value) && physical_equal(value, host),
  )
  assert_true(host.acquisition_started)
  assert_true(host.backing is Some(_))
  assert_eq(
    acquire_installed_arena_fd_reply(host, 2147483647).issue_family(),
    3,
  )
  assert_eq(current_installed_arena_reply(host).issue_family(), 6)
  let closed = close_installed_arena_reply(host)
  assert_eq(closed.operation_tag(), 4)
  assert_eq(closed.issue_family(), 0)
  assert_true(host.closed)
}
