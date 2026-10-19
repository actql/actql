///|
// These positives require the same selected derived provider in the actual
// Core, C stubs and runtime. Stock/unsupported builds fail; there is no skip,
// fake ready carrier, substitute Ledger or caller cleanup acknowledgement.
struct OriginalReadConsumerFixture {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  read : InstalledArenaOriginalRead
  descriptor : Int
  label : String
}

///|
fn original_read_consumer_fixture(
  label : String,
) -> OriginalReadConsumerFixture raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let descriptor = process_test_open(
    @utf8.encode(root + "/" + label + ".backing\u{0}"),
    2,
  )
  assert_true(descriptor >= 0)
  let page = domain_page_bytes()
  // Private property-test declarations, not an adopted numerical profile or
  // a proof that this covers Result schema/rows/renderer/control overlap.
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    64L * page,
    {
      planning_work: 64,
      attempts: 16,
      holdings: 16,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: 64L * page,
    },
    65536L,
  ).unwrap()
  host.acquire_fd(descriptor).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = match
    host
    .prepare_domain(scope, descriptor, 32L * page, {
      planning_work: 16,
      attempts: 4,
      holdings: 4,
      transfer_bytes: 4096L,
      retained_bytes: 8L * page,
      execution_bytes: 24L * page,
    })
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("consumer fixture: phase=domain issue=Pending")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  host.prepare_domain_read(domain).unwrap()
  let read = match
    host
    .prepare_domain_original_read(domain, {
      bootstrap_retained: 16384L,
      bootstrap_execution: 8192L,
      workspace_execution: 65536L,
      read_retained: 16384L,
      read_execution: 32768L,
    })
    .unwrap() {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) =>
      fail("consumer fixture: phase=read issue=Pending")
  }
  { host, domain, read, descriptor, label: root + "/" + label, }
}

///|
fn original_read_consumer_finish(
  fixture : OriginalReadConsumerFixture,
) -> Unit raise {
  fixture.host.close_domain_original_read(fixture.read).unwrap()
  assert_true(fixture.read.consumer is None && fixture.read.closed)
  fixture.host.close_domain_after_owner_ack(fixture.domain).unwrap()
  fixture.host.try_close().unwrap()
  assert_eq(process_test_close(fixture.descriptor), 0)
}

///|
test "actual original read consumer preserves its same loan and cannot start or claim twice" {
  let fixture = original_read_consumer_fixture("consumer-current")
  let host = fixture.host
  let (_, original_workspace) = host
    .borrow_domain_original_read(fixture.read)
    .unwrap()
  // Asymmetric one-short cases distinguish the same-typed retained/execution
  // arguments. Refusal must leave the original claim available and unconsumed.
  assert_true(
    host.prepare_domain_original_read_consumer(fixture.read, 16385L, 1L)
    is Err(Read(@resources.Resource(@resources.RetentionLimit))),
  )
  assert_true(
    host.prepare_domain_original_read_consumer(fixture.read, 1L, 32769L)
    is Err(Read(@resources.Resource(@resources.ExecutionLimit))),
  )
  assert_true(fixture.read.consumer is None)
  host.require_domain_original_read_current(fixture.read).unwrap()
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  let copied = { ..consumer, }
  assert_true(
    host.require_domain_original_read_consumer_current(copied)
    is Err(Read(@resources.ForeignOrigin)),
  )
  assert_true(
    host.borrow_domain_original_read_consumer_workspace(copied) is Err(_),
  )
  assert_true(host.enter_domain_original_read_consumer(copied) is Err(_))
  assert_true(host.leave_domain_original_read_consumer(copied) is Err(_))
  let other = domain_test_host()
  assert_true(
    other.require_domain_original_read_consumer_current(consumer) is Err(_),
  )
  assert_true(
    other.borrow_domain_original_read_consumer_workspace(consumer) is Err(_),
  )
  assert_true(other.enter_domain_original_read_consumer(consumer) is Err(_))
  assert_true(other.leave_domain_original_read_consumer(consumer) is Err(_))
  other.try_close().unwrap()
  host.require_domain_original_read_consumer_current(consumer).unwrap()
  assert_true(host.require_domain_original_read_current(fixture.read) is Err(_))
  assert_true(host.borrow_domain_original_read(fixture.read) is Err(_))
  assert_true(
    physical_equal(
      host.borrow_domain_original_read_consumer_workspace(consumer).unwrap(),
      original_workspace,
    ),
  )
  assert_true(
    host.prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    is Err(_),
  )
  host.enter_domain_original_read_consumer(consumer).unwrap()
  assert_true(host.enter_domain_original_read_consumer(consumer) is Err(_))
  host.leave_domain_original_read_consumer(consumer).unwrap()
  original_read_consumer_finish(fixture)
  assert_true(
    host.require_domain_original_read_consumer_current(consumer) is Err(_),
  )
  assert_true(@resources.funded_read_consumer_origin(consumer.consumer) is None)
}

///|
test "actual managed alias keeps the original read consumer and loan until physical close ACK" {
  let fixture = original_read_consumer_fixture("consumer-alias")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  // Allocate only the holder before entry. Its dynamic Bytes are created under
  // this exact read context and retained through the attempted physical close.
  let held : Ref[Bytes?] = Ref(None)
  host.enter_domain_original_read_consumer(consumer).unwrap()
  held.val = Some(@utf8.encode(fixture.label))
  host.leave_domain_original_read_consumer(consumer).unwrap()
  assert_true(host.close_domain_original_read(fixture.read) is Err(_))
  assert_true(
    fixture.read.consumer is Some(original) &&
    physical_equal(original, consumer),
  )
  assert_false(fixture.read.physical_retired.val || fixture.read.closed)
  assert_true(
    host.require_domain_original_read_consumer_current(consumer) is Err(_),
  )
  held.val = None
  original_read_consumer_finish(fixture)
  assert_true(@resources.funded_read_consumer_origin(consumer.consumer) is None)
}

///|
test "actual original read cleanup preserves escaped usage until its last alias returns" {
  println("original read usage: fixture acquisition")
  let fixture = original_read_consumer_fixture("consumer-usage-alias")
  println("original read usage: original fixture acquired")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  // Only this holder is allocated before Read entry. The original Ledger's
  // immutable usage replacement is allocated in the actual entered Read.
  let held : Ref[@resources.LedgerUsage?] = Ref(None)
  let ledger = fixture.read.ledger.unwrap()
  host.enter_domain_original_read_consumer(consumer).unwrap()
  println("original read usage: same consumer entered")
  @resources.charge_planning(ledger, 1).unwrap()
  held.val = Some(@resources.ledger_usage(ledger))
  host.leave_domain_original_read_consumer(consumer).unwrap()
  println("original read usage: original scope left")
  assert_true(host.close_domain_original_read(fixture.read) is Err(_))
  assert_false(fixture.read.physical_retired.val || fixture.read.closed)
  assert_eq(held.val.unwrap().planning_work, 1)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 1)
  assert_true(
    host.require_domain_original_read_consumer_current(consumer) is Err(_),
  )
  // Neither a copied cleanup snapshot nor logical stop acknowledges this
  // escaped old allocation. Release it, then close the same original only.
  held.val = None
  println("original read usage: external snapshot alias released")
  original_read_consumer_finish(fixture)
  assert_true(@resources.funded_read_consumer_origin(consumer.consumer) is None)
}
