///|
fn[T, E] Result::retained_execution_value(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
fn retained_cleanup_observation_foreign_controls(
  host : InstalledArenaHost,
  execution : InstalledArenaRetainedExecution,
) -> Unit raise {
  let copied = { ..execution, }
  assert_true(
    host.observe_domain_retained_execution_cleanup_scope(copied) is Err(_),
  )
  let foreign = { ..host, }
  assert_true(
    foreign.observe_domain_retained_execution_cleanup_scope(execution) is Err(_),
  )
}

///|
fn retained_execution_physical_work(
  host : InstalledArenaHost,
  execution : InstalledArenaRetainedExecution,
  page : Int64,
  retained : Ref[Array[Int]?],
  snapshot : Ref[@resources.LedgerUsage?],
) -> Unit raise {
  assert_true(
    host.observe_domain_retained_execution_cleanup_scope(execution) is Err(_),
  )
  host
  .enter_domain_retained_execution(execution)
  .retained_execution_value("retained stage 11: actual entered")
  assert_eq(
    host
    .observe_domain_retained_execution_scope(execution)
    .retained_execution_value("scope normal entered"),
    @bootstrap.BackedReadEntered,
  )
  let ledger = host
    .borrow_domain_retained_execution_ledger(execution)
    .retained_execution_value("retained stage 12: original Ledger")
  assert_true(
    physical_equal(
      ledger,
      host.borrow_domain_retained_execution_ledger(execution).unwrap(),
    ),
  )
  assert_eq(@resources.ledger_limits(ledger).execution_bytes, 64L * page)
  let reservation = @resources.reserve_capacity(ledger, 0L, 64L * page).retained_execution_value(
    "retained stage 13: same allowance",
  )
  assert_true(
    @resources.reserve_capacity(ledger, 0L, 1L)
    is Err(@resources.ExecutionLimit),
  )
  @resources.settle_capacity(ledger, reservation).retained_execution_value(
    "retained stage 14: original reservation settled",
  )
  retained.val = Some(Array::make(32, 17))
  snapshot.val = Some(@resources.ledger_usage(ledger))
  host
  .leave_domain_retained_execution(execution)
  .retained_execution_value("retained stage 15: actual leave")
  assert_eq(
    host
    .observe_domain_retained_execution_scope(execution)
    .retained_execution_value("scope normal left"),
    @bootstrap.BackedReadUnentered,
  )
  // Serial reentry has no new Ledger, delegation or zero-based usage reset.
  host
  .enter_domain_retained_execution(execution)
  .retained_execution_value("retained stage 16: original reentry")
  assert_true(
    physical_equal(
      ledger,
      host.borrow_domain_retained_execution_ledger(execution).unwrap(),
    ),
  )
  host
  .leave_domain_retained_execution(execution)
  .retained_execution_value("retained stage 17: second leave")
}

///|
fn retained_execution_physical_case(failed_entry? : Bool = false) -> Unit raise {
  // Selected same-provider diagnostic only. These numbers do not select an
  // installed candidate, prove a complete Run quote or issue normal funding.
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let page = domain_page_bytes()
  let descriptor = process_test_open(@utf8.encode(root + "/backing\u{0}"), 2)
  assert_true(descriptor >= 0)
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    256L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: 256L * page,
    },
    65536L,
  ).retained_execution_value("retained stage 1: Host")
  host.acquire_fd(descriptor).retained_execution_value("retained stage 2: FD")
  let scope = host
    .borrow_backing()
    .retained_execution_value("retained stage 3: scope")
  host
  .enter_backing_borrow_scope(scope)
  .retained_execution_value("retained stage 4: backing enter")
  let domain = match
    host
    .prepare_domain(scope, descriptor, 128L * page, {
      planning_work: 8,
      attempts: 4,
      holdings: 2,
      transfer_bytes: 4096L,
      retained_bytes: page,
      execution_bytes: 64L * page,
    })
    .retained_execution_value("retained stage 5: domain") {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("retained stage 5: partial domain")
  }
  host
  .transfer_domain(domain)
  .retained_execution_value("retained stage 6: transfer")
  host
  .leave_backing_borrow_scope(scope)
  .retained_execution_value("retained stage 7: backing leave")
  host
  .return_backing_borrow(scope)
  .retained_execution_value("retained stage 8: backing return")
  host
  .prepare_domain_read(domain)
  .retained_execution_value("retained stage 9: context")
  let execution = match
    host
    .prepare_domain_retained_execution(domain)
    .retained_execution_value("retained stage 10: issuer") {
    ReadyRetainedExecution(value) => value
    PendingRetainedExecution(_, _) => fail("retained stage 10: partial issuer")
  }
  if failed_entry {
    retained_failed_entry_cleanup_case(host, execution)
    host.close_domain_retained_execution(execution).unwrap()
    assert_true(
      execution.closed && execution.physical_retired && execution.reported,
    )
    assert_true(
      host.finish_domain_retained_execution_failed_entry_cleanup(execution)
      is Err(_),
    )
    host.close_domain_after_owner_ack(domain).unwrap()
    host.try_close().unwrap()
    assert_eq(process_test_close(descriptor), 0)
    return
  }
  assert_true(
    domain.live_channel is None &&
    domain.process is None &&
    domain.original_read is None,
  )
  assert_true(host.prepare_domain_retained_execution(domain) is Err(_))
  assert_true(host.borrow_domain_retained_execution_ledger(execution) is Err(_))
  assert_eq(
    host
    .observe_domain_retained_execution_scope(execution)
    .retained_execution_value("scope normal original prepared"),
    @bootstrap.BackedReadUnentered,
  )
  let retained : Ref[Array[Int]?] = Ref(None)
  let snapshot : Ref[@resources.LedgerUsage?] = Ref(None)
  retained_execution_physical_work(host, execution, page, retained, snapshot)
  assert_true(
    host.close_domain_after_owner_ack(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
  )
  assert_true(host.close_domain_retained_execution(execution) is Err(_))
  assert_false(execution.physical_retired || execution.closed)
  assert_true(
    host.require_domain_retained_execution_current(execution) is Err(_),
  )
  assert_true(host.observe_domain_retained_execution_scope(execution) is Err(_))
  retained.val = None
  // Replacing the control snapshot does not retire an escaped old snapshot.
  assert_true(host.close_domain_retained_execution(execution) is Err(_))
  assert_false(execution.physical_retired || execution.closed)
  host
  .enter_domain_retained_execution_cleanup(execution)
  .retained_execution_value("retained cleanup: same original frame")
  retained_cleanup_observation_foreign_controls(host, execution)
  assert_eq(
    host
    .observe_domain_retained_execution_cleanup_scope(execution)
    .retained_execution_value("scope cleanup entered"),
    @bootstrap.BackedReadEntered,
  )
  assert_true(host.observe_domain_retained_execution_scope(execution) is Err(_))
  assert_true(host.enter_domain_retained_execution_cleanup(execution) is Err(_))
  assert_true(host.borrow_domain_retained_execution_ledger(execution) is Err(_))
  assert_true(host.enter_domain_retained_execution(execution) is Err(_))
  snapshot.val = None
  host
  .leave_domain_retained_execution(execution)
  .retained_execution_value("retained cleanup: original leave")
  assert_eq(
    host
    .observe_domain_retained_execution_cleanup_scope(execution)
    .retained_execution_value("scope cleanup left"),
    @bootstrap.BackedReadUnentered,
  )
  assert_true(
    host.require_domain_retained_execution_current(execution) is Err(_),
  )
  match host.close_domain_retained_execution(execution) {
    Ok(_) => ()
    Err(Domain(@bootstrap.Bootstrap(@bootstrap.Physical(code)))) =>
      fail("retained stage 18: physical cleanup code \{code}")
    Err(Domain(_)) => fail("retained stage 18: domain cleanup issue")
    Err(Child(_)) => fail("retained stage 18: original child cleanup issue")
    Err(Initialization(_)) =>
      fail("retained stage 18: unexpected initialization cleanup")
  }
  assert_true(
    execution.closed && execution.physical_retired && execution.reported,
  )
  assert_true(host.observe_domain_retained_execution_scope(execution) is Err(_))
  assert_true(
    host.observe_domain_retained_execution_cleanup_scope(execution) is Err(_),
  )
  host
  .close_domain_after_owner_ack(domain)
  .retained_execution_value("retained stage 19: loan/region")
  host.try_close().retained_execution_value("retained stage 20: Host")
  assert_eq(process_test_close(descriptor), 0)
}

///|
fn retained_failed_entry_cleanup_case(
  host : InstalledArenaHost,
  execution : InstalledArenaRetainedExecution,
) -> Unit raise {
  assert_true(
    host.finish_domain_retained_execution_failed_entry_cleanup(execution)
    is Err(_),
  )
  // The real parent scope excludes entering the child lease. It is not a
  // fabricated entry status or a mutation of the retained original's latch.
  let parent = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(parent).unwrap()
  assert_true(host.enter_domain_retained_execution(execution) is Err(_))
  assert_true(execution.active && execution.scope_failed)
  assert_true(
    host.finish_domain_retained_execution_failed_entry_cleanup(execution)
    is Err(_),
  )
  assert_true(execution.active && !execution.physical_retired)
  host.leave_backing_borrow_scope(parent).unwrap()
  host.return_backing_borrow(parent).unwrap()
  let copied = { ..execution, }
  let foreign = { ..host, }
  assert_true(
    host.finish_domain_retained_execution_failed_entry_cleanup(copied) is Err(_),
  )
  assert_true(
    foreign.finish_domain_retained_execution_failed_entry_cleanup(execution)
    is Err(_),
  )
  assert_true(host.close_domain_retained_execution(execution) is Err(_))
  assert_true(host.leave_domain_retained_execution(execution) is Err(_))
  host.finish_domain_retained_execution_failed_entry_cleanup(execution).unwrap()
  assert_true(!execution.active && execution.scope_failed && execution.closing)
  assert_false(
    execution.physical_retired || execution.closed || execution.reported,
  )
  assert_eq(
    host.observe_domain_retained_execution_cleanup_scope(execution).unwrap(),
    @bootstrap.BackedReadUnentered,
  )
  assert_true(host.enter_domain_retained_execution(execution) is Err(_))
  assert_true(host.borrow_domain_retained_execution_ledger(execution) is Err(_))
  // A genuinely entered cleanup frame cannot be discharged by this port.
  host.enter_domain_retained_execution_cleanup(execution).unwrap()
  assert_true(
    host.finish_domain_retained_execution_failed_entry_cleanup(execution)
    is Err(_),
  )
  assert_true(execution.active && !execution.physical_retired)
  host.leave_domain_retained_execution(execution).unwrap()
}

///|
test "actual in-process domain supplies one entered ledger and retains original aliases" {
  retained_execution_physical_case()
}

///|
test "failed original entry cleanup confirms non-entry without retiring its parent" {
  retained_execution_physical_case(failed_entry=true)
}
