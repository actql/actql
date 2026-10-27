///|
#external
priv type UsageBoundaryLoader

///|
#module("node:module")
extern "js" fn usage_boundary_loader(url : String) -> UsageBoundaryLoader = "createRequire"

///|
extern "js" fn usage_boundary_url() -> String =
  #|() => import.meta.url

///|
/// The actual Core-created Array[Int64] crosses directly to the real Host
/// adapter. The one runtime callback returns that SAME array without copying,
/// padding, JSON admission or another MoonBit namespace. No provider runs.
extern "js" fn usage_boundary_observe(
  loader : UsageBoundaryLoader,
  values : Array[Int64],
  pending : Bool,
  phase : Int,
) -> Bool =
  #|(loader,values,pending,phase) => {
  #|  const assert=loader('node:assert/strict');
  #|  const api=loader('../../../../../adapters/host-common/runtime-core.mjs');
  #|  const setup={}; let reads=0;
  #|  const runtime=api.runtimeCore({strategyRemoteManagedOutputEvidenceKind:()=> 'unused test metadata',
  #|    strategyHostUsage(actual) {assert.equal(actual,setup); reads++; return values;}});
  #|  assert(Array.isArray(values)); assert.equal(values.length,13);
  #|  assert(values.every(value=>typeof value==='bigint'));
  #|  const before=[...values], usage=runtime.usage(setup);
  #|  assert.equal(reads,1); assert.equal(Object.keys(usage).length,13);
  #|  assert.equal(api.ledgerUsageHasPendingResources(values),pending);
  #|  assert.equal(api.ledgerUsageSnapshotHasPendingResources(usage),pending);
  #|  const diagnostic=api.ledgerUsageDiagnostic(values);
  #|  assert.equal(diagnostic.transferredBytes,usage.transferredBytes.toString());
  #|  assert.equal(diagnostic.peakRetentionBytes,usage.peakRetentionBytes.toString());
  #|  if(phase>=7) {assert.equal(usage.transferredBytes,9007199254740993n);
  #|    assert.equal(diagnostic.transferredBytes,'9007199254740993');
  #|    assert.equal(usage.peakRetentionBytes,3n);}
  #|  assert.deepEqual(values,before);
  #|  return true;
  #|}

///|
fn usage_boundary_check(
  loader : UsageBoundaryLoader,
  ledger : Ledger,
  phase : Int,
) raise {
  let usage = ledger_usage(ledger)
  assert_true(
    usage_boundary_observe(
      loader,
      ledger_usage_values(usage),
      ledger_usage_has_pending_resources(usage),
      phase,
    ),
  )
}

///|
test "actual Ledger usage output crosses the original JS adapter with live and spent counters" {
  // Pure numeric Ledger observations. Large transfer DATA allocates no body,
  // performs no I/O and establishes no normal Root/Run/physical admission.
  let ledger = create_ledger({
    ..backed_test_limits(),
    transfer_bytes: 9223372036854775807L,
  }).unwrap()
  let loader = usage_boundary_loader(usage_boundary_url())
  usage_boundary_check(loader, ledger, 0)
  let unused = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  usage_boundary_check(loader, ledger, 1)
  settle_reservation(ledger, unused).unwrap()
  usage_boundary_check(loader, ledger, 2)
  let capacity = reserve_capacity(ledger, 0L, 0L).unwrap()
  usage_boundary_check(loader, ledger, 3)
  settle_capacity(ledger, capacity).unwrap()
  usage_boundary_check(loader, ledger, 4)
  let delegated = reserve_execution_delegation(
    ledger,
    {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    },
    0L,
    0L,
  ).unwrap()
  usage_boundary_check(loader, ledger, 5)
  settle_execution_delegation(ledger, delegated, Some(initial_ledger_usage)).unwrap()
  usage_boundary_check(loader, ledger, 6)
  charge_planning(ledger, 2).unwrap()
  let spent = reserve_attempt(ledger, 9007199254740993L, 3L, 4L).unwrap()
  consume_reserved_attempt(ledger, spent).unwrap()
  let holding = retain_allocation(ledger, spent, 3L).unwrap()
  charge_transfer(ledger, spent, 9007199254740993L).unwrap()
  settle_reservation(ledger, spent).unwrap()
  usage_boundary_check(loader, ledger, 7)
  release_allocation(ledger, holding).unwrap()
  usage_boundary_check(loader, ledger, 8)
  let uncertain = reserve_attempt(ledger, 3L, 0L, 0L).unwrap()
  mark_transfer_uncertain(ledger, uncertain, 3L).unwrap()
  settle_reservation(ledger, uncertain).unwrap()
  usage_boundary_check(loader, ledger, 9)
}
