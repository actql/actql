///|
struct RegionOriginal {
  marker : Int
}

///|
struct RegionChild {
  marker : Int
}

///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(count : Ref[Int], condition : Bool, name : String) -> Unit {
  if !condition {
    abort("original region conformance failed: " + name)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + name)
}

///|
/// One caller-owned private FD and 64-page fixture. No process/VM is started;
/// this tests the original physical region/view before a worker consumes it.
fn main {
  let count = Ref(0)
  let page = page_bytes()
  let bytes = 64L * page
  let original : RegionOriginal = { marker: 1, }
  // The equal-valued copy remains foreign to the same original backing Owner.
  let foreign_original : RegionOriginal = { marker: original.marker, }
  let source = "0123456789012345678901234567890123456789"
  let recipe = Bytes::make(32, 29)
  let supplier = @bootstrap.prepare_installed_arena_supplier(
    original,
    source,
    recipe,
    1L,
    bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire_fd(original, 0).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("private FD backing not acquired")
  }
  host.claim(original, source, recipe, 1L).unwrap()
  let control = host.capacity_usage().allocated
  let allocation = host.allocate(original, 4L * page).unwrap()
  let region : @bootstrap.NativeBackedExecutionRegion[
    RegionOriginal,
    RegionChild,
  ] = host.issue_backed_region(original, allocation).unwrap()
  require(
    count,
    host.usage().reserved_execution_bytes == bytes &&
    host.capacity_usage().allocated == control + 4L * page &&
    host.require_current(foreign_original) is Err(ForeignOriginal),
    "original shared backing is charged once",
  )
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let first : RegionChild = { marker: 1, }
  let second : RegionChild = { marker: 2, }
  let foreign : RegionChild = { marker: first.marker, }
  let limits : @resources.LedgerLimits = {
    planning_work: 2,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 3L,
    retained_bytes: 0L,
    execution_bytes: 7L,
  }
  let window : @resources.BackedExecutionExtent = {
    offset: 0L,
    length: page,
    payload_offset: 3L,
    payload_length: 7L,
  }
  let a = match
    host
    .lend_backed_region(
      original,
      region,
      scope,
      first,
      window,
      @resources.ExclusiveWrite,
      limits,
      0L,
      0L,
    )
    .unwrap() {
    Lent(loan) => loan
    Pending(_, _) => abort("actual original FD region not lent")
  }
  let transport = host.project_backed_extent(original, a, first).unwrap()
  require(
    count,
    transport.source == source &&
    transport.recipe == recipe &&
    transport.generation == 1L &&
    transport.capacity == bytes &&
    transport.mapping_offset == control &&
    transport.mapping_length == page &&
    transport.payload_offset == 3L &&
    transport.payload_length == 7L &&
    transport.writable,
    "actual physical window and logical payload remain distinct",
  )
  require(
    count,
    host.project_backed_extent(original, a, first).unwrap() == transport,
    "same bounded projection retains original data",
  )
  require(
    count,
    host.project_backed_extent(original, a, foreign)
    is Err(Bootstrap(ForeignOriginal)),
    "equal child metadata does not convey nominal custody",
  )
  require(
    count,
    host.lend_backed_region(
      original,
      region,
      scope,
      second,
      window,
      @resources.ReadOnly,
      limits,
      0L,
      0L,
    )
    is Err(Accounting(ExtentConflict)),
    "overlapping writer is refused by the same original Owner",
  )
  let b = match
    host
    .lend_backed_region(
      original,
      region,
      scope,
      second,
      { ..window, offset: page, },
      @resources.ExclusiveWrite,
      limits,
      0L,
      0L,
    )
    .unwrap() {
    Lent(loan) => loan
    Pending(_, _) => abort("disjoint original FD writer not lent")
  }
  let btransport = host.project_backed_extent(original, b, second).unwrap()
  require(
    count,
    btransport.mapping_offset == control + page &&
    btransport.payload_length == 7L &&
    host.usage().reserved_execution_bytes == bytes,
    "disjoint writer retains one backing and its own actual range",
  )
  let av = match host.map_backed_view(original, a, first, 0).unwrap() {
    Mapped(view) => view
    PendingView(_, _) => abort("same FD extent view not mapped")
  }
  require(
    count,
    host.settle_backed_region_after_owner_ack(original, a, first, None)
    is Err(Bootstrap(ReadersPending)),
    "a live mapping cannot return its range or logical allowance",
  )
  require(
    count,
    host.close_backed_view(original, av, foreign)
    is Err(Bootstrap(ForeignOriginal)),
    "foreign child cannot close the mapped original view",
  )
  require(
    count,
    host.map_backed_view(original, a, first, 0)
    is Err(Bootstrap(AlreadyConsumed)),
    "same loan cannot create a second view",
  )
  let bv = match
    host.map_backed_view(original, b, second, 2147483647).unwrap() {
    PendingView(view, Bootstrap(Physical(-5))) => view
    _ => abort("foreign physical FD must be a typed mismatch")
  }
  require(
    count,
    host.map_backed_view(original, b, second, 0)
    is Err(Bootstrap(AlreadyConsumed)),
    "failed original map cannot silently retry with a different FD",
  )
  require(
    count,
    host.settle_backed_region_after_owner_ack(original, b, second, None)
    is Err(Bootstrap(ReadersPending)),
    "failed view retains the same cleanup record before settlement",
  )
  require(
    count,
    !host.close_backed_region(original, region).unwrap() &&
    host.project_backed_extent(original, a, first) is Err(Bootstrap(Closing)),
    "region close never reuses cached projection or discards live views",
  )
  host.close_backed_view(original, av, first).unwrap()
  host.close_backed_view(original, av, first).unwrap()
  host.close_backed_view(original, bv, second).unwrap()
  host.close_backed_view(original, bv, second).unwrap()
  // Neither view was dispatched to a worker. Both physical borrowers are now
  // actually retired; the fixture's trusted caller owns this exact unstarted ACK.
  host.settle_backed_region_after_owner_ack(original, a, first, None).unwrap()
  host.settle_backed_region_after_owner_ack(original, b, second, None).unwrap()
  require(
    count,
    host.close_backed_region(original, region).unwrap() &&
    host.usage().uncertain_transfer_bytes == 6L &&
    host.usage().reserved_execution_bytes == bytes,
    "physical return then conservative logical settlement leaves original backing held",
  )
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
  require(
    count,
    host.usage().reserved_execution_bytes == 0L &&
    host.capacity_usage().allocated == 0L,
    "original Host finally retires its own backing",
  )
  println(
    "{\"native_region_cases\":" +
    count.val.to_string() +
    ",\"passed\":" +
    count.val.to_string() +
    ",\"fixture_pages\":64,\"device\":" +
    transport.device.to_string() +
    ",\"inode\":" +
    transport.inode.to_string() +
    ",\"mapping_offset\":" +
    transport.mapping_offset.to_string() +
    ",\"mapping_length\":" +
    transport.mapping_length.to_string() +
    ",\"payload_offset\":3,\"payload_length\":7,\"vm\":0,\"worker\":0,\"public_e2e\":0}",
  )
}
