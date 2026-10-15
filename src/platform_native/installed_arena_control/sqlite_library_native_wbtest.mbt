///|
fn sqlite_test_empty_record(
  domain : InstalledArenaDomain,
) -> InstalledArenaSqliteLibrary {
  {
    domain,
    library: None,
    failure: None,
    original_issue: None,
    scope_open: false,
    closed: false,
  }
}

///|
fn sqlite_test_pending_domain(
  host : InstalledArenaHost,
) -> InstalledArenaDomain {
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  domain
}

///|
test "SQLite refuses an unprepared original read domain without registering or loading" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  assert_true(
    host.prepare_sqlite_library(
      domain, "/candidate/component.dylib", 4096L, 128,
    )
    is Err(Domain(_)),
  )
  assert_true(domain.sqlite_library is None)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "SQLite foreign Host and logical closing do not create a Library attempt" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  assert_true(
    other.prepare_sqlite_library(
      domain, "/candidate/component.dylib", 4096L, 128,
    )
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    host.prepare_sqlite_library(
      domain, "/candidate/component.dylib", 4096L, 128,
    )
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.Closing))),
  )
  assert_true(domain.sqlite_library is None)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "unregistered or substituted SQLite carrier cannot release original domain responsibility" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let original = sqlite_test_empty_record(domain)
  let copy = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(original)
  assert_true(
    host.close_sqlite_library(copy)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_false(original.closed)
  assert_true(
    host.close_domain_read(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
  )
  // This original acquisition is pending: no physical domain/read context
  // exists. Preserve its earlier Unavailable classification; full domain
  // retirement still refuses the registered unclosed Library carrier below.
  assert_true(
    host.close_domain_after_owner_ack(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
  )
  // Empty acquisition fixture only: no physical Library was ever published.
  host.close_sqlite_library(original).unwrap()
  assert_true(original.closed && !copy.closed)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "same empty partial carrier closes after logical Host closing without issuing read success" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let record = sqlite_test_empty_record(domain)
  record.original_issue = Some(Library(@sqlite.InvalidLimit))
  domain.sqlite_library = Some(record)
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    other.close_sqlite_library(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(host.current_sqlite_library(record) is Err(Domain(_)))
  host.close_sqlite_library(record).unwrap()
  host.close_sqlite_library(record).unwrap()
  assert_true(record.closed)
  assert_true(record.original_issue is Some(Library(@sqlite.InvalidLimit)))
  assert_true(host.current_sqlite_library(record) is Err(Domain(_)))
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  assert_true(
    host.close_sqlite_library(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  other.try_close().unwrap()
}

///|
test "full domain retirement breaks closed SQLite reverse registration and refuses retired handles" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let original = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(original)
  host.close_sqlite_library(original).unwrap()
  host.close_sqlite_library(original).unwrap()
  // A closed Library does not reset the live domain's acquisition history.
  assert_true(
    domain.sqlite_library is Some(value) && physical_equal(value, original),
  )
  assert_true(
    host.prepare_sqlite_library(domain, "/candidate/other.dylib", 4096L, 128)
    is Err(_),
  )
  assert_true(
    domain.sqlite_library is Some(value) && physical_equal(value, original),
  )
  host.close_domain_after_owner_ack(domain).unwrap()
  assert_true(domain.closed && original.closed)
  assert_true(domain.sqlite_library is None)
  assert_true(physical_equal(original.domain, domain))
  assert_true(
    host.current_sqlite_library(original)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    host.close_sqlite_library(original)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "unconfirmed SQLite cleanup keeps registration through refused parent retirement" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let original = sqlite_test_empty_record(domain)
  original.original_issue = Some(
    Library(@sqlite.Physical("original unconfirmed cleanup")),
  )
  domain.sqlite_library = Some(original)
  assert_true(
    host.close_domain_after_owner_ack(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
  )
  assert_false(domain.closed || original.closed)
  assert_true(
    domain.sqlite_library is Some(value) && physical_equal(value, original),
  )
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  // Empty partial fixture: cleanup acquires/rebinds no Library or read scope.
  host.close_sqlite_library(original).unwrap()
  assert_true(
    domain.sqlite_library is Some(value) && physical_equal(value, original),
  )
  host.close_domain_after_owner_ack(domain).unwrap()
  assert_true(domain.sqlite_library is None)
  assert_true(original.original_issue is Some(Library(@sqlite.Physical(_))))
  host.try_close().unwrap()
}
