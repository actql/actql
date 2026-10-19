///|
test "Runtime Read matching refuses an unregistered pair before using its read" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // Deliberately unregistered negative carrier; no acquired domain or funding.
  let record : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  assert_true(
    host.require_local_host_consuming_read_current(record, read)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    host.observe_local_host_consuming_read_scope(record, read)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(read.consumer is None && !read.ready)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "Runtime Read matching cannot adopt an unclaimed or different original" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let (foreign, other_sqlite) = local_host_resources_pending(host)
  // Counterfeit registration tests only the closed refusal path. No positive
  // current check or physical Read is fabricated by this mutation fixture.
  let record : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  host.local_host_resources = Some(record)
  assert_true(
    host.require_local_host_consuming_read_current(record, foreign)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    host.require_local_host_consuming_read_current(record, read)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable))),
  )
  for active in [None, Some(HostRead), Some(HostSqlite)] {
    record.active = active
    assert_true(
      host.observe_local_host_consuming_read_scope(record, foreign)
      is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
    )
    assert_true(
      host.observe_local_host_consuming_read_scope(record, read)
      is Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable))),
    )
    assert_true(record.active == active)
  }
  record.active = None
  assert_true(read.consumer is None && foreign.consumer is None)
  assert_false(
    record.closing || record.closed || read.closing || foreign.closing,
  )
  host.local_host_resources = None
  host.close_domain_original_read(foreign).unwrap()
  host.close_sqlite_library(other_sqlite).unwrap()
  host.close_domain_after_owner_ack(foreign.domain).unwrap()
  host.close_domain_after_owner_ack(other_sqlite.domain).unwrap()
  local_host_resources_finish_pending(host, read, sqlite)
}
