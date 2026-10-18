///|
fn local_host_resources_pending(
  host : InstalledArenaHost,
) -> (InstalledArenaOriginalRead, InstalledArenaSqliteLibrary) {
  let read_domain = sqlite_test_pending_domain(host)
  let sqlite_domain = sqlite_test_pending_domain(host)
  let read = original_read_unacquired_carrier(read_domain)
  let sqlite = sqlite_test_empty_record(sqlite_domain)
  read_domain.original_read = Some(read)
  sqlite_domain.sqlite_library = Some(sqlite)
  (read, sqlite)
}

///|
fn local_host_resources_finish_pending(
  host : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  sqlite : InstalledArenaSqliteLibrary,
) -> Unit {
  host.close_domain_original_read(read).unwrap()
  host.close_sqlite_library(sqlite).unwrap()
  host.close_domain_after_owner_ack(read.domain).unwrap()
  host.close_domain_after_owner_ack(sqlite.domain).unwrap()
  host.try_close().unwrap()
}

///|
test "Host resource binding refuses unacquired read without registering or loading SQLite" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  assert_true(host.bind_local_host_resources(read, sqlite) is Err(Read(_)))
  assert_true(host.local_host_resources is None)
  assert_true(sqlite.library is None && sqlite.failure is None)
  assert_false(read.ready || read.physical_retired.val || read.closed)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "Host resource binding refuses one domain for both purposes before any current attempt" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let same_domain = sqlite_test_empty_record(read.domain)
  assert_true(
    host.bind_local_host_resources(read, same_domain)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(host.local_host_resources is None)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "Host resource binding cannot substitute an equal-metadata foreign Host" {
  let host = domain_test_host()
  let other = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  assert_true(
    other.bind_local_host_resources(read, sqlite)
    is Err(Read(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))),
  )
  assert_true(
    host.local_host_resources is None && other.local_host_resources is None,
  )
  local_host_resources_finish_pending(host, read, sqlite)
  other.try_close().unwrap()
}

///|
test "unregistered resource pair cannot enter borrow leave or retire original custody" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // Counterfeit carrier counter, not a successfully acquired pair or scope.
  let copy : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  assert_true(host.require_local_host_resources_current(copy) is Err(Domain(_)))
  assert_true(host.enter_local_host_phase(copy, HostRead) is Err(Domain(_)))
  assert_true(host.enter_local_host_phase(copy, HostSqlite) is Err(Domain(_)))
  assert_true(host.borrow_local_host_read(copy) is Err(Domain(_)))
  assert_true(host.borrow_local_host_sqlite(copy) is Err(Domain(_)))
  assert_true(host.leave_local_host_phase(copy) is Err(Domain(_)))
  assert_true(host.enter_local_host_cleanup(copy, HostRead) is Err(Domain(_)))
  assert_true(host.close_local_host_resources(copy) is Err(Domain(_)))
  assert_false(copy.closing || copy.closed || read.closed || sqlite.closed)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "active Host phase refuses parent retirement without leaving or closing either original" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // State/identity counter only. No successful bind, C enter or allocation
  // acknowledgement is synthesized by this explicitly unacquired fixture.
  let record : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: Some(HostRead),
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  host.local_host_resources = Some(record)
  assert_true(
    host.close_local_host_resources(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
  )
  assert_true(
    record.closing && !record.closed && record.active == Some(HostRead),
  )
  assert_false(read.closed || sqlite.closed || record.sqlite_context_retired)
  assert_true(host.close_domain_after_owner_ack(read.domain) is Err(_))
  assert_true(host.close_domain_after_owner_ack(sqlite.domain) is Err(_))
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    host.local_host_resources is Some(value) && physical_equal(value, record),
  )
  assert_true(host.close_local_host_resources({ ..record, }) is Err(Domain(_)))
  // Remove only the unacquired test registration; real bound custody has no
  // public reset/unregister entry and must receive both physical close ACKs.
  host.local_host_resources = None
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "failed SQLite context retirement retains both originals and never closes the Read early" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // Unacquired identity fixture: empty Library cleanup can finish, but this
  // domain has no physical read context, so retirement must remain refused.
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
  assert_true(host.close_local_host_resources(record) is Err(Domain(_)))
  assert_true(
    record.closing && !record.closed && !record.sqlite_context_retired,
  )
  assert_true(sqlite.closed && !read.closed && !read.physical_retired.val)
  assert_true(host.close_local_host_resources(record) is Err(Domain(_)))
  assert_true(sqlite.closed && !read.closed && !record.sqlite_context_retired)
  assert_true(host.bind_local_host_resources(read, sqlite) is Err(Domain(_)))
  assert_true(host.enter_local_host_phase(record, HostRead) is Err(Domain(_)))
  assert_true(host.close_domain_after_owner_ack(read.domain) is Err(_))
  assert_true(host.close_domain_after_owner_ack(sqlite.domain) is Err(_))
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  // No successful physical pair was ever bound in this fixture.
  host.local_host_resources = None
  local_host_resources_finish_pending(host, read, sqlite)
}
