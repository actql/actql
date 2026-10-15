///|
fn read_replies(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
) -> Array[InstalledArenaDomainReply] {
  [
    prepare_installed_arena_domain_read_reply(host, domain),
    current_installed_arena_domain_read_reply(host, domain),
    enter_installed_arena_domain_read_reply(host, domain),
    leave_installed_arena_domain_read_reply(host, domain),
    cleanup_installed_arena_domain_read_reply(host, domain),
    close_installed_arena_domain_read_reply(host, domain),
  ]
}

///|
test "read reply retains the original pending domain without material or success" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let before = host.backing.unwrap().usage()
  let replies = read_replies(host, domain)
  for index = 0; index < replies.length(); index = index + 1 {
    let reply = replies[index]
    assert_eq(reply.operation_tag(), 8 + index)
    assert_eq(reply.issue_family(), 1)
    assert_true(physical_equal(reply.original_host(), host))
    assert_true(
      reply.original_domain() is Some(value) && physical_equal(value, domain),
    )
    assert_eq(reply.material_scalar(0), -1L)
    assert_eq(reply.material_source(), "")
  }
  assert_eq(host.backing.unwrap().usage(), before)
  // Host logical closing rejects new work; cleanup reaches the same original
  // pending carrier and does not pretend it ever published a C read context.
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_eq(
    prepare_installed_arena_domain_read_reply(host, domain).issue_family(),
    4,
  )
  assert_eq(
    current_installed_arena_domain_read_reply(host, domain).issue_family(),
    4,
  )
  assert_eq(
    enter_installed_arena_domain_read_reply(host, domain).issue_family(),
    4,
  )
  assert_eq(
    cleanup_installed_arena_domain_read_reply(host, domain).issue_family(),
    1,
  )
  assert_eq(
    leave_installed_arena_domain_read_reply(host, domain).issue_family(),
    1,
  )
  assert_eq(
    close_installed_arena_domain_read_reply(host, domain).issue_family(),
    1,
  )
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign or retired installed read calls cannot substitute a Host or cleanup identity" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  for reply in read_replies(other, domain) {
    assert_eq(reply.issue_family(), 2)
    assert_true(physical_equal(reply.original_host(), host))
    assert_true(
      reply.original_domain() is Some(value) && physical_equal(value, domain),
    )
  }
  assert_false(domain.closed)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  for reply in read_replies(host, domain) {
    assert_eq(reply.issue_family(), 2)
    assert_true(physical_equal(reply.original_host(), host))
  }
  host.try_close().unwrap()
  other.try_close().unwrap()
}
