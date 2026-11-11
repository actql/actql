///|
test "retained execution refuses an unprepared domain before issuing a child" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  assert_true(host.prepare_domain_retained_execution(domain) is Err(Domain(_)))
  assert_true(domain.retained_execution is None)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "retained execution preserves pending original identity and parent fence" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  // Only a custody counter. This deliberately unprepared domain has no actual
  // child Ledger, entered C context, business admission or successful Run.
  let record : InstalledArenaRetainedExecution = {
    domain,
    live: None,
    frame: None,
    ledger: None,
    initialization_cleanup: None,
    owns_read: false,
    nonmodel_prepared_work_selected: false,
    child_started: false,
    active: false,
    scope_failed: false,
    physical_retired: false,
    reported: false,
    ready: false,
    closing: false,
    closed: false,
  }
  domain.retained_execution = Some(record)
  assert_true(
    host.observe_domain_retained_execution_cleanup({ ..record, })
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    other.observe_domain_retained_execution_cleanup(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(host.observe_domain_retained_execution_cleanup(record) is Err(_))
  assert_true(
    host.close_domain_retained_execution({ ..record, })
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    other.close_domain_retained_execution(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(host.borrow_domain_retained_execution_ledger(record) is Err(_))
  assert_true(host.enter_domain_retained_execution(record) is Err(_))
  assert_true(
    host.close_domain_after_owner_ack(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
  )
  assert_false(record.closed || record.physical_retired)
  host.close_domain_retained_execution(record).unwrap()
  assert_true(record.closed)
  assert_true(host.observe_domain_retained_execution_cleanup(record) is Err(_))
  assert_false(record.physical_retired || record.child_started)
  host.close_domain_retained_execution(record).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}
