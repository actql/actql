///|
test "Business child cleanup retries the same failed physical entry after original parent unwind" {
  // Selected physical diagnostic only; these finite fixture limits are not an
  // installed command candidate or a complete operational envelope.
  let bytes = 16777216L
  let backing = initial_crypto_backing_open(bytes)
  assert_true(backing.current())
  let host = @initial_arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  host.acquire_fd(backing.descriptor()).unwrap()
  let provision = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(provision).unwrap()
  let limits : @initial_resources.LedgerLimits = {
    planning_work: 8,
    attempts: 4,
    holdings: 2,
    transfer_bytes: 4096L,
    retained_bytes: 65536L,
    execution_bytes: 4194304L,
  }
  let domain = match
    host
    .prepare_domain(provision, backing.descriptor(), 8388608L, limits)
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("partial fixture domain")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(provision).unwrap()
  host.return_backing_borrow(provision).unwrap()
  host.prepare_domain_read(domain).unwrap()
  let execution = match
    host.prepare_domain_retained_execution(domain).unwrap() {
    ReadyRetainedExecution(value) => value
    PendingRetainedExecution(_, _) => fail("partial fixture execution")
  }
  let business : LocalCommandBusinessOriginal = {
    selected_profile: None,
    initial_window_bytes: None,
    initial_domain_bytes: None,
    profile: {
      domain_bytes: 8388608L,
      kind: SourceFreeCompute,
      payload_facility_bytes: 4259840L,
      limits,
    },
    domain: Some(domain),
    execution: Some(execution),
    operation: None,
    request_input: None,
    request_intent: None,
    request_intake_units: 0L,
    request_read_failure: None,
    request_initial: None,
    request_parent: None,
    request_body: None,
    request_run: None,
    request_retiring: false,
    model_work: [],
    effect_model: None,
    values_work: None,
    values_failure: None,
    store: None,
    store_failure: None,
    store_parent: None,
    store_parent_failure: None,
    store_root: None,
    store_root_failure: None,
    store_root_operation: None,
    publication_publisher: None,
    _retained_publication_service: None,
    publication_results: None,
    publication_pending: None,
    publication_failure: None,
    _retained_publication_commit_failure: None,
    _retained_publication_cleanup_failure: None,
    publication_attempted: false,
    publication_result: None,
    run_receipt_original: None,
    publication_retired: false,
    result_binding: None,
    result_service: None,
    result_session: None,
    result_material: None,
    result_sink: None,
    result_refusal: None,
    result_cleanup_issue: None,
    active: false,
  }
  // An actual entered parent excludes the child Read. The failed constructor
  // owns the attempted entry even though no C child frame was installed.
  let parent = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(parent).unwrap()
  assert_true(business.enter_children_cleanup(host) is Err(_))
  assert_true(business.active)
  assert_true(
    business.execution is Some(original) && physical_equal(original, execution),
  )
  assert_true(host.observe_domain_retained_execution_scope(execution) is Err(_))
  assert_true(
    host.observe_domain_retained_execution_cleanup_scope(execution) is Err(_),
  )
  // The same blocked parent must still prevent an apparent cleanup ACK.
  assert_true(business.enter_children_cleanup(host) is Err(_))
  assert_true(business.active)
  host.leave_backing_borrow_scope(parent).unwrap()
  host.return_backing_borrow(parent).unwrap()
  // This is the changed caller boundary: retry through D's actual helper,
  // rather than invoking E's failed-entry recovery directly in the fixture.
  business.enter_children_cleanup(host).unwrap()
  assert_true(business.active)
  assert_true(
    host.observe_domain_retained_execution_cleanup_scope(execution)
    is Ok(@initial_bootstrap.BackedReadEntered),
  )
  assert_true(host.borrow_domain_retained_execution_ledger(execution) is Err(_))
  assert_true(host.close_domain_retained_execution(execution) is Err(_))
  host.leave_domain_retained_execution(execution).unwrap()
  business.active = false
  host.close_domain_retained_execution(execution).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  assert_true(backing.current())
  assert_true(backing.close_checked())
}

///|
// Trusted installer control record, not a public constructor, Host, domain or
// capacity grant. The enclosing initial Crypto original retains this descriptor
// separately until actual Library/context/mapping retirement has acknowledged.
type InitialCryptoBacking

///|
extern "C" fn initial_crypto_backing_open(
  bytes : Int64,
) -> InitialCryptoBacking = "actql_initial_crypto_backing_open"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::current(
  original : InitialCryptoBacking,
) -> Bool = "actql_initial_crypto_backing_current"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::descriptor(
  original : InitialCryptoBacking,
) -> Int = "actql_initial_crypto_backing_descriptor"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::close_checked(
  original : InitialCryptoBacking,
) -> Bool = "actql_initial_crypto_backing_close"
