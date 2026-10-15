///|
test "worker original projection cannot turn pending physical preparation into accounting DATA" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let original = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let before = host.backing.unwrap().usage()
  assert_true(host.project_domain_original(original) is Err(_))
  assert_eq(host.backing.unwrap().usage(), before)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(original).unwrap()
  host.try_close().unwrap()
}

///|
test "worker original projection refuses foreign closing and retired installed child" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let original = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let before = host.backing.unwrap().usage()
  assert_true(
    other.project_domain_original(original)
    is Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)),
  )
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    host.project_domain_original(original)
    is Err(@bootstrap.Bootstrap(@bootstrap.Closing)),
  )
  assert_eq(host.backing.unwrap().usage(), before)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(original).unwrap()
  assert_true(
    host.project_domain_original(original)
    is Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)),
  )
  host.try_close().unwrap()
  other.try_close().unwrap()
}
