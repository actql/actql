///|
#external
priv type CleanupTestLoader

///|
// The test runner is ESM, so obtain the normal Node loader explicitly.
extern "js" fn cleanup_test_url() -> String =
  #|() => import.meta.url

///|
#module("node:module")
extern "js" fn cleanup_create_loader(url : String) -> CleanupTestLoader = "createRequire"

///|
extern "js" fn cleanup_original_root(
  loader : CleanupTestLoader,
  prepared : Ref[Int],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,prepared,current) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(prepared,{planningWork:10000,attempts:10,holdings:10,transferBytes:300000n,retainedBytes:32000000n,executionBytes:134217728n},current,()=>false)

///|
test "Strategy keeps settled holding stage when actual Common reservation settlement refuses" {
  let current_action : Ref[(() -> Unit)?] = Ref(None)
  let prepared_original = Ref(1)
  let root = cleanup_original_root(
    cleanup_create_loader(cleanup_test_url()),
    prepared_original,
    () => if current_action.val is Some(action) { action() },
  )
  let admission = @resources.prepare_node_managed_run_admission(
    root, prepared_original,
  ).unwrap()
  let ledger = @resources.start_node_managed_run_admission(admission).unwrap()
  let (run, _) = captured_graph_fixture(original_ledger=Some(ledger))
  let bootstrap = @resources.reserve_capacity(ledger, 1024L, 1024L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 16, 16, 0,
  ).unwrap()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let cleaned = Ref(false)
  let releases = Ref(0)
  let prepared = @connector.bind_prepared_materializing_execution(
    choice,
    candidate,
    {
      transfer_bytes: 100L,
      retained_bytes: 100L,
      scratch_bytes: 10L,
      execution_bytes: 100L,
    },
    [],
    fn(payload) {
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() {  },
        dispose: fn() {  },
        settled: fn() {  },
        scratch_released: () => cleaned.val,
        retention_released: () => cleaned.val,
        released: () => releases.val += 1,
        ready: () => Ok(()),
      }
      Ok((payload, operations))
    },
    retained_bytes=() => Ok(40L),
  ).unwrap()
  let (_, execution) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  @strategy.charge_task_execution_transfer(run, execution, 23L).unwrap()
  @strategy.settle_task_execution(run, execution, true).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, execution, () => {
      Err(MissingOutput)
    })
    is Err(MissingOutput),
  )
  @strategy.close_task_execution(run, execution)
  let origin = Ref(7)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = @resources.claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  @resources.enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let calls = Ref(0)
  let parked = Ref(false)
  current_action.val = Some(() => {
    calls.val += 1
    if calls.val == 2 {
      // First currentness belongs to successful holding release; the second
      // parks the same real Ledger immediately before reservation settlement.
      current_action.val = None
      parked.val = @resources.park_original_resource_consumer(consumer, origin)
        is Ok(_)
    }
  })
  cleaned.val = true
  assert_true(
    @strategy.refresh_task_execution_cleanup(run, execution)
    is Err(ResourceParked),
  )
  assert_true(parked.val)
  let pending = @resources.ledger_usage(ledger)
  assert_eq(pending.held_bytes, 0L)
  assert_eq(pending.transferred_bytes, 23L)
  assert_eq(releases.val, 0)
  // A second observation reaches the remaining reservation, not the already
  // released holding (which would yield ClosedHolding and mask ResourceParked).
  assert_true(
    @strategy.refresh_task_execution_cleanup(run, execution)
    is Err(ResourceParked),
  )
  assert_eq(@resources.ledger_usage(ledger), pending)
  assert_eq(releases.val, 0)
}
