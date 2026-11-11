///|
// Negative custody fixture only. It has no admitted physical child, entered C
// frame, Account, Source, actual Work or manufactured physical acknowledgement.
fn nonmodel_entry_negative_carrier(
  host : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  sqlite : InstalledArenaSqliteLibrary,
) -> InstalledArenaNonModelWorkEntry {
  let domain = sqlite_test_pending_domain(host)
  let execution : InstalledArenaRetainedExecution = {
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
  domain.retained_execution = Some(execution)
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 1L,
    retained_bytes: 32L,
    execution_bytes: 32L,
  }).unwrap()
  let control = @resources.reserve_capacity(ledger, 16L, 16L).unwrap()
  let pair : InstalledArenaLocalHostResources = {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  let entry : InstalledArenaNonModelWorkEntry = {
    original: Ref(None),
    host,
    pair,
    read,
    execution,
    ledger,
    control: DedicatedNonModelWorkCapacity(control),
    ledger_view: Some(ledger),
    retained_bytes: 16L,
    execution_bytes: 16L,
    growing: false,
    constructor_entered: false,
    claimed: false,
    finished: false,
    settled: false,
    closed: false,
  }
  entry.original.val = Some(entry)
  entry
}

///|
fn close_nonmodel_entry_negative_carrier(
  entry : InstalledArenaNonModelWorkEntry,
) -> Unit raise {
  entry.original.val = None
  guard entry.control is DedicatedNonModelWorkCapacity(control) else {
    fail("original dedicated fixture")
  }
  @resources.settle_capacity(entry.ledger, control).unwrap()
  entry.host.close_domain_retained_execution(entry.execution).unwrap()
  entry.host.close_domain_after_owner_ack(entry.execution.domain).unwrap()
  local_host_resources_finish_pending(entry.host, entry.read, entry.pair.sqlite)
}

///|
// This fixture exercises nominal identity and invalid-scope refusals only.
// It is not an eligible physical original/copy comparison.
test "copied nonmodel entry predicate and unentered refusal preserve original token" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let entry = nonmodel_entry_negative_carrier(host, read, sqlite)
  let copy = { ..entry, }
  let before = entry.usage()
  assert_true(entry.is_original())
  assert_false(copy.is_original())
  assert_true(copy.take_entered_ledger(entry.execution, 16L, 16L) is None)
  assert_false(copy.owns_only_control())
  assert_true(copy.grow_in_original_read(24L, 24L) is Err(Unavailable))
  assert_true(entry.grow_in_original_read(24L, 24L) is Err(Unavailable))
  assert_eq(entry.retained_bytes, 16L)
  assert_eq(entry.execution_bytes, 16L)
  assert_false(entry.growing)
  assert_true(
    copy.prepare_constructor_in_entered_scope(24L, 24L, 8L) is Err(Unavailable),
  )
  assert_true(
    entry.prepare_constructor_in_entered_scope(24L, 24L, 8L) is Err(Unavailable),
  )
  assert_false(entry.constructor_entered)
  assert_false(entry.constructor_scope_for(host, entry.pair, read))
  assert_false(copy.constructor_scope_for(host, entry.pair, read))
  assert_false(copy.finish_business_cleanup())
  assert_false(copy.cancel_unclaimed_in_original_read())
  assert_false(copy.close_after_original_return())
  assert_eq(entry.usage(), before)
  assert_false(entry.claimed || entry.finished || entry.settled || entry.closed)
  assert_true(
    host.prepare_domain_nonmodel_work_entry(
      entry.pair,
      read,
      entry.execution,
      16L,
      16L,
    )
    is None,
  )
  assert_eq(entry.usage(), before)
  close_nonmodel_entry_negative_carrier(entry)
}

///|
test "nonmodel post-report retry requires this entry's own successful settlement latch" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let entry = nonmodel_entry_negative_carrier(host, read, sqlite)
  assert_true(entry.finalization_owns_report())
  // Pure branch regression only, not a fake report or physical-close success.
  entry.execution.reported = true
  assert_false(entry.finalization_owns_report())
  entry.settled = true
  assert_true(entry.finalization_owns_report())
  assert_false(entry.close_after_original_return())
  entry.execution.reported = false
  entry.settled = false
  close_nonmodel_entry_negative_carrier(entry)
}

///|
test "nonmodel pristine precondition refuses unrelated original reservation and pending attempt" {
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 8L,
    retained_bytes: 32L,
    execution_bytes: 32L,
  }).unwrap()
  assert_true(nonmodel_entry_pristine(ledger))
  let bytes = @resources.reserve_capacity(ledger, 1L, 1L).unwrap()
  assert_false(nonmodel_entry_pristine(ledger))
  @resources.settle_capacity(ledger, bytes).unwrap()
  assert_true(nonmodel_entry_pristine(ledger))
  let attempt = @resources.reserve_attempt(ledger, 1L, 1L, 1L).unwrap()
  assert_false(nonmodel_entry_pristine(ledger))
  @resources.settle_reservation(ledger, attempt).unwrap()
  assert_true(nonmodel_entry_pristine(ledger))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
}
