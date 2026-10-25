///|
struct LiveOriginal {
  marker : Int
}

///|
struct LiveChild {
  marker : Int
}

///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(count : Ref[Int], condition : Bool, name : String) -> Unit {
  if !condition {
    abort("original live-child conformance failed: " + name)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + name)
}

///|
// Disposable original FD on stdin, same64-page fixture as domain conformance.
// Ref runtime stands in for the trusted physical issuer's slot: VM/channel
// binding is not supplied or accepted by this accounting/Native conformance.
fn main {
  let count = Ref(0)
  let page = page_bytes()
  let original : LiveOriginal = { marker: 1, }
  let child : LiveChild = { marker: 1, }
  let foreign : LiveChild = { marker: 1, }
  let runtime = Ref(1)
  let source = "0123456789012345678901234567890123456789"
  let recipe = Bytes::make(32, 29)
  let limits : @resources.LedgerLimits = {
    planning_work: 2,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 3L,
    retained_bytes: 0L,
    execution_bytes: 16L * page,
  }
  let supplier = @bootstrap.prepare_installed_arena_supplier(
    original,
    source,
    recipe,
    1L,
    64L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 64L * page,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire_fd(original, 0).unwrap() {
    Acquired(host) => host
    _ => abort("original conformance FD unavailable")
  }
  host.claim(original, source, recipe, 1L).unwrap()
  let allocation = host.allocate(original, 24L * page).unwrap()
  let region : @bootstrap.NativeBackedExecutionRegion[LiveOriginal, LiveChild] = host
    .issue_backed_region(original, allocation)
    .unwrap()
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
        length: 24L * page,
        payload_offset: page,
        payload_length: 16L * page,
      },
      @resources.ExclusiveWrite,
      limits,
      0L,
      0L,
    )
    .unwrap() {
    Lent(loan) => loan
    _ => abort("original conformance region unavailable")
  }
  let view = match host.map_backed_view(original, loan, child, 0).unwrap() {
    Mapped(view) => view
    _ => abort("original conformance view unavailable")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(domain) => domain
    _ => abort("original conformance domain unavailable")
  }
  require(
    count,
    host.prepare_backed_live_child(original, domain, child, runtime)
    is Err(Bootstrap(Unavailable)),
    "untransferred domain refuses live access",
  )
  host.transfer_backed_domain(original, domain, child).unwrap()
  host.leave_borrow_scope(original, scope).unwrap()
  let before = host.usage()
  require(
    count,
    original.marker == 1 &&
    child.marker == foreign.marker &&
    host.prepare_backed_live_child(original, domain, foreign, runtime)
    is Err(Bootstrap(ForeignOriginal)),
    "foreign child cannot acquire the original accounting use",
  )
  let live = match
    host.prepare_backed_live_child(original, domain, child, runtime).unwrap() {
    LiveChildReady(live) => live
    _ => abort("original live access unavailable")
  }
  require(
    count,
    host.usage() == before,
    "same allowance adds no parent reservation or quota",
  )
  require(
    count,
    host.require_backed_read_context_current(original, domain, child)
    is Err(Bootstrap(Unavailable)),
    "accounting use does not claim a parent physical read context",
  )
  require(
    count,
    host.enter_backed_read_cleanup(original, domain, child)
    is Err(Bootstrap(Unavailable)),
    "accounting-only parent cannot enter a child cleanup frame",
  )
  require(
    count,
    host.prepare_backed_live_child(original, domain, child, runtime)
    is Err(Bootstrap(AlreadyConsumed)),
    "same original borrow cannot issue another access",
  )
  require(
    count,
    host.admit_backed_live_child(original, live, Ref(1))
    is Err(Bootstrap(ForeignOriginal)),
    "same-valued foreign runtime slot cannot admit",
  )
  require(
    count,
    host.backed_live_child_state(original, live, runtime)
    is Err(Bootstrap(Unavailable)),
    "live preparation alone is not an admitted lifecycle observation",
  )
  host.admit_backed_live_child(original, live, runtime).unwrap()
  require(
    count,
    host.backed_live_child_state(original, live, runtime)
    is Ok(@resources.LiveOpen),
    "same original live state observes Open without changing usage",
  )
  require(
    count,
    host.backed_live_child_state(original, live, Ref(1))
    is Err(Bootstrap(ForeignOriginal)),
    "equal-valued foreign runtime cannot observe the original live lifecycle",
  )
  require(
    count,
    host.backed_live_child_limits(original, live, runtime).unwrap() == limits,
    "admitted DATA describes only the original bounded allowance",
  )
  require(
    count,
    host.admit_backed_live_child(original, live, runtime)
    is Err(Accounting(@resources.LiveChildAlreadyAdmitted)),
    "lost admission response does not permit another admission",
  )
  let usage : @resources.LedgerUsage = {
    // This synthetic cumulative report owns no live child-side tokens.
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    planning_work: 1,
    attempts: 1,
    holdings: 0,
    transferred_bytes: 1L,
    uncertain_transfer_bytes: 1L,
    reserved_transfer_bytes: 0L,
    held_bytes: 0L,
    reserved_retention_bytes: 0L,
    reserved_execution_bytes: 16L * page,
    peak_retention_bytes: 0L,
  }
  host.report_backed_live_child(original, live, runtime, usage).unwrap()
  let reported = host.usage()
  require(
    count,
    reported.planning_work == before.planning_work + 1 &&
    reported.attempts == before.attempts + 1 &&
    reported.transferred_bytes == 1L &&
    reported.uncertain_transfer_bytes == 1L &&
    reported.reserved_execution_bytes == before.reserved_execution_bytes,
    "cumulative report charges the original parent exactly once",
  )
  host.report_backed_live_child(original, live, runtime, usage).unwrap()
  require(
    count,
    host.usage() == reported,
    "duplicate cumulative report adds no charge",
  )
  require(
    count,
    host.report_backed_live_child(original, live, runtime, {
      ..usage,
      planning_work: 0,
    })
    is Err(_) &&
    host.usage() == reported,
    "regressing usage is refused without resetting the parent",
  )
  require(
    count,
    host.close_backed_domain(original, domain, child)
    is Err(Accounting(@resources.CleanupPending)),
    "live access keeps the original read borrow pending",
  )
  require(
    count,
    !host.close_backed_region(original, region).unwrap(),
    "pending original domain cannot return its allocation",
  )
  host.stop_backed_live_child(original, live, runtime).unwrap()
  let stopped_usage = host.usage()
  require(
    count,
    host.backed_live_child_state(original, live, runtime)
    is Ok(@resources.LiveClosing) &&
    host.usage() == stopped_usage,
    "same original Closing remains observable without report or settlement",
  )
  require(
    count,
    host.backed_live_child_limits(original, live, runtime) is Err(_),
    "logical stop refuses fresh child work",
  )
  host.report_backed_live_child(original, live, runtime, usage).unwrap()
  require(
    count,
    host.usage() == reported,
    "original cleanup can still report after logical stop",
  )
  // This test has no VM/channel or escaped runtime projection. Only its own
  // fixture slot is retired here; this is not product child-retirement evidence.
  host
  .retire_backed_live_child_after_owner_ack(original, live, runtime)
  .unwrap()
  require(
    count,
    host.backed_live_child_state(original, live, runtime)
    is Err(Bootstrap(ForeignOriginal)),
    "retired original runtime cannot regain its live lifecycle",
  )
  require(
    count,
    host.usage() == reported,
    "live reference retirement returns no capacity or quota",
  )
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_domain(original, domain, child).unwrap()
  require(
    count,
    host.usage().reserved_execution_bytes == before.reserved_execution_bytes,
    "domain cleanup does not settle the original loan",
  )
  host.close_backed_view(original, view, child).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  require(
    count,
    host.usage().transferred_bytes == 1L &&
    host.usage().uncertain_transfer_bytes == 2L,
    "unknown final usage conservatively consumes the same remaining quota",
  )
  require(
    count,
    host.close_backed_region(original, region).unwrap(),
    "original allocation retires only after separate view and loan cleanup",
  )
  exercise_channel_partial(count, host, original, page, scope)
  require(
    count,
    host.allocate(original, 24L * page)
    is Err(Resource(@resources.RetentionLimit)),
    "retained original allocations refuse a third extent within the unchanged64 pages",
  )
  host.return_borrow(original, scope).unwrap()
  // The first original view/loan has already retired. Return its actual backing
  // reader before retiring its allocation, then borrow the SAME Host again.
  host.retire(original, allocation).unwrap()
  let next_scope = host.borrow_backing(original).unwrap()
  exercise_pre_spawn_channel(count, host, original, page, next_scope)
  host.return_borrow(original, next_scope).unwrap()
  host.try_close(original).unwrap()
  require(
    count,
    host.usage().reserved_execution_bytes == 0L,
    "actual parent close finally returns its one backing reservation",
  )
  if count.val != 68 {
    abort(
      "original live-child conformance discovery must execute exactly68 cases",
    )
  }
  println(
    "{\"success\":true,\"discovered\":68,\"executed\":68,\"passed\":68,\"failed\":0,\"VM\":0,\"public_e2e\":0}",
  )
}
