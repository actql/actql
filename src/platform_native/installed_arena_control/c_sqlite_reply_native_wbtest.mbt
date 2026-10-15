///|
test "SQLite refusal reply preserves original Host/domain without a Library or permission" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let reply = prepare_installed_arena_sqlite_reply(
    host, domain, "/candidate/component.dylib", 4096L, 128,
  )
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 1)
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(physical_equal(reply.original_domain(), domain))
  assert_true(reply.original_library() is None)
  assert_true(domain.sqlite_library is None)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign SQLite reply retains true original references and refuses its cleanup" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let original = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(original)
  let current = current_installed_arena_sqlite_reply(other, original)
  let close = close_installed_arena_sqlite_reply(other, original)
  for reply in [current, close] {
    assert_true(physical_equal(reply.original_host(), host))
    assert_true(physical_equal(reply.original_domain(), domain))
    assert_true(
      reply.original_library() is Some(value) && physical_equal(value, original),
    )
    assert_eq(reply.issue_family(), 2)
  }
  assert_eq(current.operation_tag(), 2)
  assert_eq(close.operation_tag(), 3)
  assert_false(original.closed)
  host.close_sqlite_library(original).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "SQLite typed reasons are closed categories not inferred from diagnostic strings" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let reasons = [
    @sqlite.UnsupportedTarget,
    @sqlite.InvalidName,
    @sqlite.InvalidLimit,
    @sqlite.LibraryLoad(""),
    @sqlite.DatabaseOpen(""),
    @sqlite.DatabaseClosed,
    @sqlite.NotFound,
    @sqlite.Collision,
    @sqlite.Busy,
    @sqlite.BodyTooLarge,
    @sqlite.CapacityExceeded,
    @sqlite.Physical(""),
  ]
  for i = 0; i < reasons.length(); i = i + 1 {
    let reply : InstalledArenaSqliteReply = {
      operation: PrepareSqlite,
      host,
      domain,
      original: None,
      issue: Some(Library(reasons[i])),
    }
    assert_eq(reply.issue_family(), 9 + i)
    assert_true(reply.original_library() is None)
  }
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "SQLite close ACK belongs only to same original operation and does not retire parent" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let original = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(original)
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  let reply = close_installed_arena_sqlite_reply(host, original)
  assert_eq(reply.operation_tag(), 3)
  assert_eq(reply.issue_family(), 0)
  assert_true(reply.issue_description().is_empty())
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(
    reply.original_library() is Some(value) && physical_equal(value, original),
  )
  assert_true(original.closed && !domain.closed && !host.closed)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
