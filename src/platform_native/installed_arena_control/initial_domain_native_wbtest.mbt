///|
test "first domain uses same charged backing and does not reuse retired first identity" {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let descriptor = process_test_open(
    @utf8.encode(root + "/initial-domain.backing\u{0}"),
    2,
  )
  assert_true(descriptor >= 0)
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire_fd(descriptor).unwrap()
  let backing = host.original_backing().unwrap()
  let candidate = backing.initial_payload_capacity(host).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = match
    host.prepare_initial_domain(scope, descriptor, 2, 1, 1, 3L).unwrap() {
    PreparedDomain(domain) => domain
    PendingDomain(_, _) =>
      fail("first physical domain must acquire its original extent")
  }
  host.transfer_domain(domain).unwrap()
  let material = host.project_prepared_domain(domain).unwrap()
  assert_eq(material.extent.payload_length, candidate)
  assert_eq(material.limits.execution_bytes, candidate)
  assert_eq(material.limits.retained_bytes, 0L)
  assert_eq(
    backing.capacity_usage().allocated,
    backing.capacity_usage().capacity,
  )
  assert_true(
    host.prepare_initial_domain(scope, descriptor, 2, 1, 1, 3L)
    is Err(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)),
  )
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  let later = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(later).unwrap()
  assert_true(
    host.prepare_initial_domain(later, descriptor, 2, 1, 1, 3L)
    is Err(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)),
  )
  host.leave_backing_borrow_scope(later).unwrap()
  host.return_backing_borrow(later).unwrap()
  host.try_close().unwrap()
  assert_eq(process_test_close(descriptor), 0)
}

///|
test "first domain mapping refusal retains same pending record and cleanup" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  // This anonymous parent cannot claim an unrelated FD. Allocation and loan
  // custody already exist and must remain on the original pending record.
  let reply = prepare_installed_arena_initial_domain_reply(
    host, scope, 2147483647, 2, 1, 1, 3L,
  )
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 6)
  let domain = reply.original_domain().unwrap()
  assert_true(physical_equal(domain.host, host))
  assert_eq(host.domains.length(), 1)
  assert_false(domain.closed)
  assert_true(host.require_domain_current(domain) is Err(_))
  assert_true(
    host.prepare_initial_domain(scope, 2147483647, 2, 1, 1, 3L)
    is Err(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)),
  )
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "first domain refuses foreign scope before registering any domain" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = other.borrow_backing().unwrap()
  other.enter_backing_borrow_scope(scope).unwrap()
  let reply = prepare_installed_arena_initial_domain_reply(
    host, scope, 2147483647, 2, 1, 1, 3L,
  )
  assert_eq(reply.issue_family(), 2)
  assert_true(reply.original_domain() is None && host.domains.is_empty())
  assert_true(physical_equal(reply.original_host(), host))
  other.leave_backing_borrow_scope(scope).unwrap()
  other.return_backing_borrow(scope).unwrap()
  other.try_close().unwrap()
  host.try_close().unwrap()
}

///|
test "first domain does not infer a fresh initial arena from a retired generic allocation" {
  let host = domain_test_host()
  let allocated = host.allocate(page_bytes_ffi()).unwrap()
  host.retire(allocated).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let reply = prepare_installed_arena_initial_domain_reply(
    host, scope, 2147483647, 2, 1, 1, 3L,
  )
  assert_eq(reply.issue_family(), 3)
  assert_true(reply.original_domain() is None && host.domains.is_empty())
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.try_close().unwrap()
  assert_true(
    host.prepare_initial_domain(scope, 2147483647, 2, 1, 1, 3L)
    is Err(@bootstrap.Bootstrap(@bootstrap.Closing)),
  )
}
