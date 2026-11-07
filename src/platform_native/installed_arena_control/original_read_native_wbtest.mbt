///|
fn original_read_test_budget() -> InstalledArenaOriginalReadBudget {
  // Diagnostic declarations, not a selected installed numerical profile.
  {
    bootstrap_retained: 1L,
    bootstrap_execution: 1L,
    workspace_execution: 1L,
    read_retained: 1L,
    read_execution: 1L,
  }
}

///|
fn original_read_unacquired_carrier(
  domain : InstalledArenaDomain,
) -> InstalledArenaOriginalRead {
  // Custody/identity counter only. The pending anonymous domain has no FD
  // context, original child Ledger, workspace, claim or successful read.
  {
    domain,
    live: None,
    frame: None,
    ledger: None,
    bootstrap: None,
    inventory: None,
    workspace: None,
    claim: None,
    pair: None,
    consumer: None,
    funded_retained_bytes: 0L,
    funded_execution_bytes: 0L,
    physical_retired: Ref(false),
    owns_read: false,
    child_started: false,
    read_settled: false,
    inventory_finished: false,
    report_complete: false,
    ready: false,
    closing: false,
    closed: false,
  }
}

///|
test "parent original read refuses an unprepared domain before custody or child issuance" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let before = host.domains.length()
  assert_true(
    host.prepare_domain_original_read(domain, original_read_test_budget())
    is Err(Domain(_)),
  )
  assert_true(domain.original_read is None && domain.sqlite_library is None)
  assert_eq(host.domains.length(), before)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "copied or foreign joined read carrier cannot close original custody" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let record = original_read_unacquired_carrier(domain)
  domain.original_read = Some(record)
  assert_true(
    host.close_domain_original_read({ ..record, })
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    other.close_domain_original_read(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    other.borrow_domain_original_read(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_false(record.closed || record.physical_retired.val)
  host.close_domain_original_read(record).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "unacquired read cleanup returns no physical ACK and retains the domain attempt tombstone" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let record = original_read_unacquired_carrier(domain)
  domain.original_read = Some(record)
  assert_true(
    host.close_domain_after_owner_ack(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
  )
  host.close_domain_original_read(record).unwrap()
  host.close_domain_original_read(record).unwrap()
  assert_true(record.closed && record.closing)
  assert_false(record.physical_retired.val)
  assert_true(
    domain.original_read is Some(original) && physical_equal(original, record),
  )
  assert_true(
    host.borrow_domain_original_read(record)
    is Err(Read(@resources.CleanupPending)),
  )
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  assert_true(domain.original_read is None)
  assert_true(
    host.close_domain_original_read(record)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  host.try_close().unwrap()
}

///|
test "original unacquired cleanup remains possible after Host closing without granting read" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let record = original_read_unacquired_carrier(domain)
  domain.original_read = Some(record)
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(
    host.borrow_domain_original_read(record)
    is Err(Read(@resources.CleanupPending)),
  )
  host.close_domain_original_read(record).unwrap()
  assert_false(record.physical_retired.val)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
