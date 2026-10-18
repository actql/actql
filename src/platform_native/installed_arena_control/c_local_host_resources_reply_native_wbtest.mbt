///|
test "refused Host resources binding reply retains both original inputs without issuing a pair" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let reply = bind_installed_local_host_resources_reply(host, read, sqlite)
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_origin(), 2)
  assert_true(reply.issue_family() != 0)
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(physical_equal(reply.sqlite_host(), host))
  assert_true(physical_equal(reply.original_read(), read))
  assert_true(physical_equal(reply.original_sqlite(), sqlite))
  assert_true(reply.original_resources() is None)
  assert_false(reply.close_confirmed())
  assert_true(host.local_host_resources is None)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "foreign Host resources reply retains the true original Hosts instead of its target" {
  let host = domain_test_host()
  let other = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let reply = bind_installed_local_host_resources_reply(other, read, sqlite)
  assert_eq(reply.issue_origin(), 2)
  assert_eq(reply.issue_family(), 2)
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(physical_equal(reply.sqlite_host(), host))
  assert_true(physical_equal(reply.original_read(), read))
  assert_true(physical_equal(reply.original_sqlite(), sqlite))
  assert_false(reply.close_confirmed())
  assert_true(
    host.local_host_resources is None && other.local_host_resources is None,
  )
  local_host_resources_finish_pending(host, read, sqlite)
  other.try_close().unwrap()
}

///|
test "unknown Host resources operation tags perform no action on their original carrier" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // Counterfeit identity only: no C scope is entered by this fixture.
  let record : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: Some(HostRead),
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  for tag in [-1, 0, 1, 9, 2147483647] {
    let reply = operate_installed_local_host_resources_reply(host, record, tag)
    assert_eq(reply.operation_tag(), 0)
    assert_eq(reply.issue_origin(), 1)
    assert_eq(reply.issue_family(), 1)
    assert_true(
      reply.original_resources() is Some(value) && physical_equal(value, record),
    )
    assert_false(reply.close_confirmed())
    assert_true(record.active == Some(HostRead))
    assert_false(
      record.closing || record.closed || read.closed || sqlite.closed,
    )
  }
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "nested original Unknown remains distinct from refused child and SQLite target issue" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // Getter projections only, not an executed physical operation.
  let unknown : InstalledArenaLocalHostResourcesReply = {
    operation: 2,
    read,
    sqlite,
    original: None,
    issue: Some(Read(Child(@resources.Unknown))),
  }
  assert_eq(unknown.issue_origin(), 2)
  assert_eq(unknown.issue_family(), 9)
  let refused = { ..unknown, issue: Some(Read(Child(@resources.Unavailable))), }
  assert_eq(refused.issue_origin(), 2)
  assert_eq(refused.issue_family(), 10)
  let sqlite_issue = {
    ..unknown,
    issue: Some(Sqlite(Library(@sqlite.UnsupportedTarget))),
  }
  assert_eq(sqlite_issue.issue_origin(), 3)
  assert_eq(sqlite_issue.issue_family(), 9)
  assert_false(
    unknown.close_confirmed() ||
    refused.close_confirmed() ||
    sqlite_issue.close_confirmed(),
  )
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "a success-shaped nonclose reply or absent original is never a cleanup ACK" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let record : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  let projection : InstalledArenaLocalHostResourcesReply = {
    operation: 8,
    read,
    sqlite,
    original: None,
    issue: None,
  }
  assert_false(projection.close_confirmed())
  assert_false({ ..projection, original: Some(record), }.close_confirmed())
  assert_eq(projection.issue_family(), 0)
  assert_eq(projection.issue_origin(), 0)
  assert_false(read.closed || sqlite.closed || record.closed)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "foreign cleanup reply preserves its exact unregistered pair without touching originals" {
  let host = domain_test_host()
  let other = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let record : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  let reply = operate_installed_local_host_resources_reply(other, record, 8)
  assert_eq(reply.operation_tag(), 8)
  assert_eq(reply.issue_origin(), 1)
  assert_eq(reply.issue_family(), 2)
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(
    reply.original_resources() is Some(value) && physical_equal(value, record),
  )
  assert_false(reply.close_confirmed() || record.closing || record.closed)
  assert_false(read.closed || sqlite.closed)
  local_host_resources_finish_pending(host, read, sqlite)
  other.try_close().unwrap()
}
