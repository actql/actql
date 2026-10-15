///|
fn original_read_reply_domain(
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
test "unprepared read reply retains the actual domain without issuing a carrier" {
  let host = domain_test_host()
  let domain = original_read_reply_domain(host)
  let reply = prepare_installed_arena_original_read_reply(
    host, domain, 1L, 1L, 1L, 1L, 1L,
  )
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 1)
  assert_true(reply.original_read() is None)
  assert_true(physical_equal(reply.original_domain(), domain))
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(domain.original_read is None)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign read preparation reply never replaces the actual Host or domain" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = original_read_reply_domain(host)
  let reply = prepare_installed_arena_original_read_reply(
    other, domain, 1L, 1L, 1L, 1L, 1L,
  )
  assert_eq(reply.issue_family(), 2)
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(reply.original_read() is None)
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "original read projection preserves imported Unknown apart from known refusal" {
  let host = domain_test_host()
  let domain = original_read_reply_domain(host)
  // Immutable getter projection only, not successful physical admission.
  let unknown : InstalledArenaOriginalReadReply = {
    operation: ObserveOriginalRead,
    domain,
    original: None,
    issue: Some(Child(@resources.Unknown)),
  }
  assert_eq(unknown.issue_family(), 9)
  assert_eq(
    { ..unknown, issue: Some(Child(@resources.Unavailable)), }.issue_family(),
    10,
  )
  assert_eq(
    { ..unknown, issue: Some(Read(@resources.CleanupPending)), }.issue_family(),
    11,
  )
  assert_eq(
    { ..unknown, issue: Some(Buffer(@buffers.CleanupPending)), }.issue_family(),
    12,
  )
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign and copied read replies retain original cleanup identity" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = original_read_reply_domain(host)
  let record = original_read_unacquired_carrier(domain)
  domain.original_read = Some(record)
  let foreign = current_installed_arena_original_read_reply(other, record)
  assert_eq(foreign.operation_tag(), 2)
  assert_eq(foreign.issue_family(), 2)
  assert_true(physical_equal(foreign.original_host(), host))
  assert_true(
    foreign.original_read() is Some(value) && physical_equal(value, record),
  )
  let copied = close_installed_arena_original_read_reply(host, { ..record, })
  assert_eq(copied.operation_tag(), 6)
  assert_eq(copied.issue_family(), 2)
  assert_false(record.closed)
  host.close_domain_original_read(record).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "known empty carrier close reply is distinct from read and physical retirement" {
  let host = domain_test_host()
  let domain = original_read_reply_domain(host)
  let record = original_read_unacquired_carrier(domain)
  domain.original_read = Some(record)
  let closed = close_installed_arena_original_read_reply(host, record)
  assert_eq(closed.operation_tag(), 6)
  assert_eq(closed.issue_family(), 0)
  assert_true(record.closed && !record.physical_retired.val)
  assert_true(
    closed.original_read() is Some(value) && physical_equal(value, record),
  )
  assert_eq(
    close_installed_arena_original_read_reply(host, record).issue_family(),
    0,
  )
  assert_eq(
    current_installed_arena_original_read_reply(host, record).issue_family(),
    11,
  )
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
