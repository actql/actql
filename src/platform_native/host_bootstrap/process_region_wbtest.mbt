///|
#borrow(path)
extern "C" fn process_fixture_open(path : Bytes, flags : Int) -> Int = "open"

///|
extern "C" fn process_fixture_close(descriptor : Int) -> Int = "close"

///|
struct ProcessRegionTestFixture {
  original : BootstrapTestOriginal
  child : BootstrapTestOriginal
  host : NativeHostBootstrap[BootstrapTestOriginal]
  allocation : NativeBootstrapAllocation[BootstrapTestOriginal]
  region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ]
  loan : NativeBackedExecutionLoan[BootstrapTestOriginal, BootstrapTestOriginal]
  domain : NativeBackedExecutionDomain[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ]
  descriptor : Int
}

///|
fn process_fixture_root() -> String {
  @env.get_env_var("ACTQL_TEST_NATIVE_PROCESS_REGION_ROOT").unwrap()
}

///|
/// Fresh, precreated 0600 64-page FD per case. No old Run/database is opened.
/// Test control/FD/process overhead is outside this arena fixture, not funded
/// by an ordinary numerical profile or another execution-byte reservation.
fn process_fixture(label : String) -> ProcessRegionTestFixture raise {
  let original = { identity: 71, }
  let child = { identity: 72, }
  let page = test_page_bytes_ffi()
  let path = process_fixture_root() + "/" + label + ".backing\u{0}"
  let descriptor = process_fixture_open(@utf8.encode(path), 2)
  assert_true(descriptor >= 0)
  let supplier = test_supplier(original, 64L * page)
  let host = match supplier.acquire_fd(original, descriptor).unwrap() {
    Acquired(host) => host
    Pending(_, _) => fail("fresh original FD acquisition failed")
  }
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let allocation = host.allocate(original, 48L * page).unwrap()
  let region = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let loan = match
    host
    .lend_backed_region(
      original,
      region,
      scope,
      child,
      {
        offset: 0L,
        length: 48L * page,
        payload_offset: page,
        payload_length: 32L * page,
      },
      @resources.ExclusiveWrite,
      backed_test_limits(32L * page),
      0L,
      0L,
    )
    .unwrap() {
    Lent(loan) => loan
    Pending(_, _) => fail("fresh original exclusive loan failed")
  }
  let view = match
    host.map_backed_view(original, loan, child, descriptor).unwrap() {
    Mapped(view) => view
    PendingView(_, _) => fail("fresh original view failed")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(domain) => domain
    DomainPending(_, _) => fail("fresh original domain failed")
  }
  host.transfer_backed_domain(original, domain, child).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  { original, child, host, allocation, region, loan, domain, descriptor, }
}

///|
fn process_fixture_holder(
  label : String,
) -> @executor.NativeScopedExecutorHolder raise {
  let slot = @executor.open_native_executor_slot(
    process_fixture_root() + "/" + label + ".slot",
  ).unwrap()
  assert_true(slot.try_acquire().unwrap())
  match slot.prepare_scoped_holder() {
    @executor.Ready(holder) => holder
    @executor.Refused(_, _) => fail("fresh original scoped holder failed")
  }
}

///|
fn process_fixture_finish(value : ProcessRegionTestFixture) -> Unit raise {
  value.host
  .close_backed_domain(value.original, value.domain, value.child)
  .unwrap()
  value.host
  .close_backed_view(value.original, value.domain.view, value.child)
  .unwrap()
  // Unknown final usage remains conservative; physical cleanup is no zero-use
  // or never-sent report. It does not acknowledge any external business action.
  value.host
  .settle_backed_region_after_owner_ack(
    value.original,
    value.loan,
    value.child,
    None,
  )
  .unwrap()
  assert_true(
    value.host.close_backed_region(value.original, value.region).unwrap(),
  )
  value.host.retire(value.original, value.allocation).unwrap()
  value.host.try_close(value.original).unwrap()
  assert_eq(process_fixture_close(value.descriptor), 0)
  assert_true(value.host.closed)
  assert_eq(value.host.usage().reserved_execution_bytes, 0L)
  assert_true(value.host.usage().uncertain_transfer_bytes > 0L)
}

///|
test "prepared process binding blocks ordinary retirement until same original abandonment" {
  let value = process_fixture("prepared")
  let holder = process_fixture_holder("prepared")
  let record = match
    value.host
    .bind_prepared_process_region(
      value.original,
      value.domain,
      value.child,
      holder,
      value.descriptor,
    )
    .unwrap() {
    ProcessRegionReady(record) => record
    _ => fail("fresh pre-spawn capture failed")
  }
  assert_true(
    value.host.close_backed_domain(value.original, value.domain, value.child)
    is Err(Bootstrap(ReadersPending)),
  )
  assert_true(
    value.host.bind_prepared_process_region(
      value.original,
      value.domain,
      value.child,
      holder,
      value.descriptor,
    )
    is Err(_),
  )
  value.host.abandon_prepared_process_region(value.original, record).unwrap()
  value.host.abandon_prepared_process_region(value.original, record).unwrap()
  assert_true(value.domain.process_region is None)
  assert_true(record.retired)
  process_fixture_finish(value)
}

///|
test "known descriptor capture refusal retains same preparation for cleanup" {
  let value = process_fixture("capture-refusal")
  let holder = process_fixture_holder("capture-refusal")
  let record = match
    value.host
    .bind_prepared_process_region(
      value.original,
      value.domain,
      value.child,
      holder,
      -1,
    )
    .unwrap() {
    ProcessRegionPending(record, Domain(Bootstrap(Physical(-1)))) => record
    _ => fail("invalid descriptor must return original pending carrier")
  }
  assert_true(
    value.domain.process_region is Some(selected) &&
    physical_equal(selected, record),
  )
  assert_false(record.retired)
  value.host.abandon_prepared_process_region(value.original, record).unwrap()
  process_fixture_finish(value)
}

///|
fn process_fixture_stop(
  holder : @executor.NativeScopedExecutorHolder,
) -> @executor.NativeScopedExecutorStop raise {
  for _attempt in 0..<100 {
    match holder.poll_stop().unwrap() {
      Some(stop) => return stop
      None => @executor.native_wait_milliseconds(20)
    }
  }
  fail("original scoped stop not confirmed within fixture deadline")
}

///|
test "foreign stop cannot retire the original region and stopped startup uses ordinary close" {
  let value = process_fixture("startup")
  let holder = process_fixture_holder("startup")
  let foreign = process_fixture_holder("foreign")
  let record = match
    value.host
    .bind_prepared_process_region(
      value.original,
      value.domain,
      value.child,
      holder,
      value.descriptor,
    )
    .unwrap() {
    ProcessRegionReady(record) => record
    _ => fail("fresh original process capture failed")
  }
  foreign.spawn_with_channel("/bin/true", []).unwrap()
  let foreign_stop = process_fixture_stop(foreign)
  assert_true(
    value.host.retire_stopped_process_region(
      value.original,
      record,
      foreign_stop,
    )
    is Err(Process(_)),
  )
  assert_false(record.retired)
  assert_false(record.physical_retired)
  assert_false(value.domain.closed)
  assert_false(value.loan.physical_returned)
  assert_true(foreign_stop.close())
  // This original child stops before acquiring its allocator borrow. The
  // retained prepared domain must still close through its ordinary rules.
  holder.spawn_with_channel("/bin/true", []).unwrap()
  let stop = process_fixture_stop(holder)
  assert_true(
    value.host.abandon_prepared_process_region(value.original, record)
    is Err(Process(_)),
  )
  value.host
  .retire_stopped_process_region(value.original, record, stop)
  .unwrap()
  value.host
  .retire_stopped_process_region(value.original, record, stop)
  .unwrap()
  assert_true(value.domain.closed && value.domain.view.closed && record.retired)
  assert_false(value.loan.physical_returned)
  process_fixture_finish(value)
}
