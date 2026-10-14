///|
extern "C" fn domain_page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn domain_test_host() -> InstalledArenaHost {
  let bytes = 64L * domain_page_bytes()
  let host = prepare_installed_arena_host("0123456789012345678901234567890123456789",
    Bytes::make(32, 17), 1L, bytes,
    { planning_work: 20, attempts: 8, holdings: 4, transfer_bytes: 30L,
      retained_bytes: 0L, execution_bytes: bytes }, 65536L).unwrap()
  host.acquire().unwrap()
  host
}

///|
fn domain_test_prepare(host : InstalledArenaHost, scope : InstalledArenaBackingBorrow,
  bytes : Int64) -> InstalledArenaDomainReply {
  prepare_installed_arena_domain_reply(host, scope, 2147483647, bytes,
    2, 1, 1, 3L, 0L, bytes)
}

///|
test "pending physical domain reply keeps original host record and rejects current success" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  // The anonymous parent is not an FD region. No physical child was published;
  // its logical reservation still belongs to the original pending record.
  let reply = domain_test_prepare(host, scope, 16L * domain_page_bytes())
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 6)
  assert_true(physical_equal(reply.original_host(), host))
  let domain = reply.original_domain().unwrap()
  assert_true(physical_equal(domain.host, host))
  assert_eq(current_installed_arena_domain_reply(host, domain).issue_family(), 1)
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  assert_eq(close_installed_arena_domain_reply(host, domain).issue_family(), 0)
  assert_true(domain.closed)
  assert_eq(close_installed_arena_domain_reply(host, domain).issue_family(), 0)
  host.try_close().unwrap()
  assert_true(host.closed && host.domains.is_empty())
}

///|
test "foreign target retains actual domain host and cannot release original cleanup" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes()).original_domain().unwrap()
  let denied = close_installed_arena_domain_reply(other, domain)
  assert_eq(denied.operation_tag(), 6)
  assert_eq(denied.issue_family(), 2)
  assert_true(physical_equal(denied.original_host(), host))
  assert_false(domain.closed)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  assert_eq(close_installed_arena_domain_reply(host, domain).issue_family(), 0)
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "pre-reservation domain refusal never fabricates a domain handle" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  let reply = domain_test_prepare(host, scope, 0L)
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 1)
  assert_true(reply.original_domain() is None)
  assert_eq(host.domains.length(), 0)
  host.return_backing_borrow(scope).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign backing scope is refused before domain record registration" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = other.borrow_backing().unwrap()
  let reply = domain_test_prepare(host, scope, 16L * domain_page_bytes())
  assert_eq(reply.issue_family(), 2)
  assert_true(reply.original_domain() is None)
  assert_eq(host.domains.length(), 0)
  other.return_backing_borrow(scope).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}
