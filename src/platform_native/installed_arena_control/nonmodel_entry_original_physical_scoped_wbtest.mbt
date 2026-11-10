///|
// Keep the exact lower refusal until the harness renders this terminal error.
// The original partial domain remains registered with its Host. This adds no
// cleanup, retry or acknowledgement and constructs no diagnostic String here.
suberror EligibleEntryDomainFailure {
  EligibleEntryDomainFailure(String, @bootstrap.NativeBackedExecutionIssue)
}

///|
impl Show for EligibleEntryDomainFailure with fn output(self, logger) {
  let EligibleEntryDomainFailure(stage, issue) = self
  logger.write_string("eligible entry: ")
  logger.write_string(stage)
  logger.write_string(" domain pending: ")
  logger.write_string(@debug.to_string(issue))
}

///|
// Keep the Read-created entry/copy in this lexical owner. Returning from this
// helper drops both before the parent Read pair can physically retire.
fn nonmodel_eligible_original_work(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
  control_bytes : Int64,
) -> Bool raise {
  host
  .enter_local_host_phase(pair, HostRead)
  .retained_execution_value("eligible entry: original Read enter")
  let entry = match
    host.prepare_domain_nonmodel_work_entry(
      pair, read, execution, control_bytes, control_bytes,
    ) {
    Some(Ok(ReadyNonModelWorkEntry(value))) => value
    Some(Ok(PendingNonModelWorkEntry(_))) =>
      fail("eligible entry: original preparation pending")
    Some(Err(_)) => fail("eligible entry: original preparation refused")
    None => fail("eligible entry: wrong preparation scope")
  }
  let copied = { ..entry, }
  assert_true(entry.is_original())
  assert_false(copied.is_original())
  // The original could cancel in this exact Read cut. A copied projection
  // must not settle its token, even before either projection has been claimed.
  assert_false(copied.cancel_unclaimed_in_original_read())
  assert_true(entry.owns_only_control())
  assert_false(entry.claimed || entry.finished || entry.settled || entry.closed)
  host
  .leave_local_host_phase(pair)
  .retained_execution_value("eligible entry: original Read leave")
  host
  .enter_domain_retained_execution(execution)
  .retained_execution_value("eligible entry: actual business enter")
  // Only primitive observations and the preowned Option are used in business.
  // Assertion messages are deferred until after actual retirement; an
  // unexpected failed transition remains a failed diagnostic, not a cleanup
  // ACK or a claim that its error rendering fits the success-only 240B cut.
  let eligible = host.nonmodel_entry_scopes_match(
      pair, read, execution, true, false,
    ) &&
    entry.owns_only_control() &&
    @resources.capacity_reservation_matches(
      entry.ledger,
      entry.control,
      control_bytes,
      control_bytes,
    ) &&
    !entry.claimed &&
    !entry.finished &&
    !entry.settled &&
    !entry.closed
  let copy_refused = copied.take_entered_ledger(
      execution, control_bytes, control_bytes,
    )
    is None
  let original_unchanged = !entry.claimed &&
    !entry.finished &&
    !entry.settled &&
    !entry.closed &&
    entry.owns_only_control()
  let original_taken = match
    entry.take_entered_ledger(execution, control_bytes, control_bytes) {
    Some(ledger) => physical_equal(ledger, execution.ledger.unwrap())
    None => false
  }
  let original_reuse_refused = entry.take_entered_ledger(
      execution, control_bytes, control_bytes,
    )
    is None
  let copied_reuse_refused = copied.take_entered_ledger(
      execution, control_bytes, control_bytes,
    )
    is None
  let same_control = entry.owns_only_control() &&
    entry.usage().attempts == 0 &&
    entry.usage().reserved_attempts == 0 &&
    entry.usage().transferred_bytes == 0L
  let finished = entry.finish_business_cleanup()
  host
  .leave_domain_retained_execution(execution)
  .retained_execution_value("eligible entry: actual business leave")
  // This is the existing original C retirement and exact-token settlement,
  // not a field assignment or caller acknowledgement. Failure stops here.
  assert_true(entry.close_after_original_return())
  assert_true(
    execution.physical_retired && execution.reported && execution.closed,
  )
  assert_true(entry.settled && entry.closed && entry.original.val is None)
  assert_eq(entry.usage().live_reservations, 0)
  assert_eq(entry.usage().reserved_retention_bytes, 0L)
  assert_eq(entry.usage().reserved_execution_bytes, 0L)
  assert_eq(entry.usage().attempts, 0)
  assert_eq(entry.usage().reserved_attempts, 0)
  assert_eq(entry.usage().transferred_bytes, 0L)
  assert_true(entry.close_after_original_return())
  eligible &&
  copy_refused &&
  original_unchanged &&
  original_taken &&
  original_reuse_refused &&
  copied_reuse_refused &&
  same_control &&
  finished
}

///|
// Same selected provider and original components as the existing pair and
// retained-execution diagnostics. This is not a normal installed profile.
fn nonmodel_physical_entry_case(
  claimed : Bool,
  retained_frame? : Bool = false,
  constructing? : Bool = false,
) -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let sqlite_path = @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap()
  let page = domain_page_bytes()
  // Direct arena preparation adds the two constructor/grow state words;
  // its actual shallow copy retains those same two words as DATA.
  // H34/R42/S81 includes both original and copy before consumer admission.
  let read_entry_bytes = 34L * 16L + 42L * 8L + 81L * 8L
  assert_eq(read_entry_bytes, 1528L)
  // Successful direct enter-after-C plus leave-before-C: H8/R4/S10.
  // This reservation remains open until actual business C retirement.
  let control_bytes = 8L * 16L + 4L * 8L + 10L * 8L
  assert_eq(control_bytes, 240L)
  // Compose the existing pair and retained-execution outer control baselines,
  // plus the complete claimed-entry close frontier H33/R14/S79. These are
  // distinct owners, not unexplained spare business capacity. The subset used
  // here has no Client operation projection; the full frontier is conservative.
  let outer_entry_bytes = 33L * 16L + 14L * 8L + 79L * 8L
  assert_eq(outer_entry_bytes, 1272L)
  let outer_control_bytes = 65536L + 65536L + outer_entry_bytes
  let read_extent = 7168L * page
  let sqlite_extent = 64L * page
  let business_extent = 64L * page
  let read_limits : @resources.LedgerLimits = {
    planning_work: 2,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 3L,
    // This distinct case adds exactly one 32B simultaneous frame to its
    // declared child allowance. Root limits, backing extents, attempts and
    // both existing case declarations remain unchanged.
    retained_bytes: 32L * page +
    read_entry_bytes +
    (if retained_frame { 32L } else { 0L }),
    execution_bytes: 6144L * page,
  }
  let sqlite_limits : @resources.LedgerLimits = {
    planning_work: 2,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 3L,
    retained_bytes: 0L,
    execution_bytes: 48L * page,
  }
  let business_limits : @resources.LedgerLimits = {
    planning_work: 8,
    // This case exercises only byte control, nominal take and original
    // retirement. Imported admission/current, reserve_capacity and settlement
    // consume no child attempt. No dispatch/send capability is exercised.
    attempts: 0,
    holdings: 2,
    transfer_bytes: 4096L,
    // This distinct constructor case admits its real current/backing/resize
    // frame plus the retained String; original take-only cases stay unchanged.
    retained_bytes: if constructing {
      16L * page
    } else {
      page
    },
    execution_bytes: 32L * page,
  }
  // The SAME root pays one reserved backing attempt plus one provisioning
  // attempt per domain, in addition to each child's delegated allowance.
  // Three domains with the former business allowance of four required twelve,
  // not eight. Keep the root fixed and delegate only what this case uses.
  let root_attempts = 8
  let backing_attempts = 1
  let domain_provisioning_attempts = 3
  assert_eq(
    backing_attempts +
    domain_provisioning_attempts +
    read_limits.attempts +
    sqlite_limits.attempts +
    business_limits.attempts,
    root_attempts,
  )
  let read_necessary = @bootstrap.execution_domain_necessary_bytes(
    read_extent,
    read_limits.retained_bytes + read_limits.execution_bytes,
  )
  let sqlite_necessary = @bootstrap.execution_domain_necessary_bytes(
    sqlite_extent,
    sqlite_limits.retained_bytes + sqlite_limits.execution_bytes,
  )
  let business_necessary = @bootstrap.execution_domain_necessary_bytes(
    business_extent,
    business_limits.retained_bytes + business_limits.execution_bytes,
  )
  let backing_control = @bootstrap.command_backing_control_necessary_bytes(
    8192L * page,
  ).unwrap()
  assert_true(read_necessary > 0L && read_necessary <= read_extent)
  assert_true(sqlite_necessary > 0L && sqlite_necessary <= sqlite_extent)
  assert_true(business_necessary > 0L && business_necessary <= business_extent)
  assert_true(
    backing_control + read_extent + sqlite_extent + business_extent <=
    8192L * page,
  )
  let descriptor = process_test_open(@utf8.encode(root + "/backing\u{0}"), 2)
  assert_true(descriptor >= 0)
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    8192L * page,
    {
      planning_work: 20,
      attempts: root_attempts,
      holdings: 8,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: 8192L * page,
    },
    outer_control_bytes,
  ).retained_execution_value("eligible entry: Host")
  host.acquire_fd(descriptor).retained_execution_value("eligible entry: FD")
  let backing = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(backing).unwrap()
  let read_domain = match
    host.prepare_domain(backing, descriptor, read_extent, read_limits).unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, issue) => raise EligibleEntryDomainFailure("Read", issue)
  }
  host.transfer_domain(read_domain).unwrap()
  let sqlite_domain = match
    host
    .prepare_domain(backing, descriptor, sqlite_extent, sqlite_limits)
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, issue) => raise EligibleEntryDomainFailure("SQLite", issue)
  }
  host.transfer_domain(sqlite_domain).unwrap()
  let business_domain = match
    host
    .prepare_domain(backing, descriptor, business_extent, business_limits)
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, issue) =>
      raise EligibleEntryDomainFailure("business", issue)
  }
  host.transfer_domain(business_domain).unwrap()
  host.leave_backing_borrow_scope(backing).unwrap()
  host.return_backing_borrow(backing).unwrap()
  host.prepare_domain_read(read_domain).unwrap()
  host.prepare_domain_read(sqlite_domain).unwrap()
  host.prepare_domain_read(business_domain).unwrap()
  let execution = match
    host.prepare_domain_retained_execution(business_domain).unwrap() {
    ReadyRetainedExecution(value) => value
    PendingRetainedExecution(_, _) =>
      fail("eligible entry: original execution pending")
  }
  let read = match
    host
    .prepare_domain_original_read(read_domain, {
      bootstrap_retained: 16L * page,
      bootstrap_execution: 16L * page,
      workspace_execution: 4096L * page,
      read_retained: 16L * page + read_entry_bytes,
      read_execution: 1024L * page + read_entry_bytes,
    })
    .unwrap() {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) => fail("eligible entry: original Read pending")
  }
  let sqlite = match
    host
    .prepare_sqlite_library(sqlite_domain, sqlite_path, 32L * page, 128)
    .unwrap() {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("eligible entry: original SQLite pending")
  }
  let pair = host.bind_local_host_resources(read, sqlite).unwrap()
  let consumer = host
    .prepare_domain_original_read_consumer(
      read,
      16L * page + read_entry_bytes,
      1024L * page + read_entry_bytes,
    )
    .unwrap()
  let proved = if constructing {
    nonmodel_constructor_original_work(host, pair, read, execution)
  } else if claimed {
    nonmodel_eligible_original_work(host, pair, read, execution, control_bytes)
  } else {
    nonmodel_unclaimed_original_work(
      host,
      pair,
      read,
      execution,
      control_bytes,
      retained_frame~,
    )
  }
  assert_true(consumer.scope == ConsumerScopeLeft)
  // The distinct business owner must retire its real loan before the Read
  // pair. This helper has already dropped its Read-created entry and copy.
  host.close_domain_after_owner_ack(business_domain).unwrap()
  host.close_local_host_resources(pair).unwrap()
  assert_true(pair.closed && read.closed && sqlite.closed)
  host.close_domain_after_owner_ack(read_domain).unwrap()
  host.close_domain_after_owner_ack(sqlite_domain).unwrap()
  host.try_close().unwrap()
  assert_eq(process_test_close(descriptor), 0)
  assert_true(proved)
}

///|
fn nonmodel_unclaimed_original_work(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
  control_bytes : Int64,
  retained_frame? : Bool = false,
) -> Bool raise {
  host.enter_local_host_phase(pair, HostRead).unwrap()
  if retained_frame {
    let before_retained = read.funded_retained_bytes
    let before_execution = read.funded_execution_bytes
    // One additional fixed H1/S2 frame, alongside existing paid backing.
    host
    .prepare_domain_original_read_retained_construction(read, 32L, 32L, 32L)
    .unwrap()
    assert_eq(read.funded_retained_bytes, before_retained + 32L)
    assert_eq(read.funded_execution_bytes, before_execution + 32L)
  }
  let entry = match
    host.prepare_domain_nonmodel_work_entry(
      pair, read, execution, control_bytes, control_bytes,
    ) {
    Some(Ok(ReadyNonModelWorkEntry(value))) => value
    _ => fail("Expected original unclaimed entry")
  }
  let copied = { ..entry, }
  assert_false(entry.claimed || entry.finished)
  assert_true(entry.owns_only_control())
  // Neither a copied carrier nor an active C scope may acknowledge retirement.
  assert_false(copied.close_after_original_return())
  assert_false(entry.close_after_original_return())
  host.leave_local_host_phase(pair).unwrap()
  assert_false(copied.close_after_original_return())
  // No business borrower was entered. The actual original C retirement and
  // exact reservation settlement remain required; no claimed flag is forged.
  assert_true(entry.close_after_original_return())
  assert_true(
    execution.physical_retired && execution.closed && execution.reported,
  )
  assert_true(entry.settled && entry.closed && entry.original.val is None)
  assert_eq(entry.usage().live_reservations, 0)
  assert_eq(entry.usage().attempts, 0)
  assert_eq(entry.usage().transferred_bytes, 0L)
  assert_true(entry.close_after_original_return())
  true
}

///|
test "eligible copied entry refuses while the same original takes once and physically retires" {
  nonmodel_physical_entry_case(true)
}

///|
test "unclaimed original entry retires only after actual parent scope return" {
  nonmodel_physical_entry_case(false)
}

///|
test "simultaneous Read frame preserves prior backing through original retirement" {
  nonmodel_physical_entry_case(false, retained_frame=true)
}

///|
// Business payload is scoped inside this helper, so its original String has
// dropped before the outer owner attempts actual context retirement.
fn nonmodel_constructor_phases(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
  entry : InstalledArenaNonModelWorkEntry,
) -> Bool {
  host.leave_local_host_phase(pair).unwrap()
  host.enter_domain_retained_execution(execution).unwrap()
  entry.prepare_constructor_in_entered_scope(8192L, 32768L, 256L).unwrap()
  // Actual fixed UTF16 payload:64 units+terminator/header fits the independent
  // 256B placement, unrelated to either logical byte reservation dimension.
  let held = String::make(64, 'x')
  let first = entry.constructor_scope_for(host, pair, read)
  host.leave_domain_retained_execution(execution).unwrap()
  host.enter_local_host_phase(pair, HostRead).unwrap()
  let cancel_refused = !entry.cancel_unclaimed_in_original_read()
  entry.grow_in_original_read(12288L, 49152L).unwrap()
  let token_same = entry.owns_only_control() &&
    entry.usage().live_reservations == 1
  host.leave_local_host_phase(pair).unwrap()
  host.enter_domain_retained_execution(execution).unwrap()
  entry.prepare_constructor_in_entered_scope(16384L, 65536L, 256L).unwrap()
  let second = entry.constructor_scope_for(host, pair, read) &&
    held.length() == 64 &&
    held[0] == 'x'
  let ledger = entry.take_entered_ledger(execution, 16384L, 65536L).unwrap()
  let same = physical_equal(ledger, execution.ledger.unwrap()) &&
    entry.usage().attempts == 0 &&
    entry.usage().holdings == 0 &&
    entry.usage().transferred_bytes == 0L
  let finished = entry.finish_business_cleanup()
  host.leave_domain_retained_execution(execution).unwrap()
  first && second && token_same && cancel_refused && same && finished
}

///|
fn nonmodel_constructor_original_work(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  execution : InstalledArenaRetainedExecution,
) -> Bool raise {
  host.enter_local_host_phase(pair, HostRead).unwrap()
  let entry = match
    host.prepare_domain_nonmodel_work_entry(pair, read, execution, 4096L, 8192L) {
    Some(Ok(ReadyNonModelWorkEntry(value))) => value
    _ => fail("constructor original entry")
  }
  entry.grow_in_original_read(8192L, 32768L).unwrap()
  let proved = nonmodel_constructor_phases(host, pair, read, execution, entry)
  // Actual context retirement/settlement after all returned payload aliases
  // dropped, not a manually changed field or a synthetic cleanup receipt.
  assert_true(entry.close_after_original_return())
  assert_true(
    execution.physical_retired && execution.reported && execution.closed,
  )
  let usage = entry.usage()
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.attempts, 0)
  assert_eq(usage.transferred_bytes, 0L)
  proved
}

///|
test "same original constructor backing grows across Read and business before one IO borrow" {
  nonmodel_physical_entry_case(true, constructing=true)
}
