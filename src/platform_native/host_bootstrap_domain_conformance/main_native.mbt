///|
struct DomainOriginal {
  marker : Int
}

///|
struct DomainChild {
  marker : Int
}

///|
priv type Probe

///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
extern "C" fn probe(bytes : Int64) -> Probe = "actql_domain_probe"

///|
#borrow(value)
extern "C" fn probe_status(value : Probe) -> Int = "actql_domain_probe_status"

///|
#borrow(value)
extern "C" fn probe_retire(value : Probe) -> Int = "actql_domain_probe_retire"

///|
fn require(count : Ref[Int], condition : Bool, name : String) -> Unit {
  if !condition {
    abort("domain custody conformance failed: " + name)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + name)
}

///|
/// Same 64-page private FD, not a complete worker/VM/product funding supplier.
fn main {
  let count = Ref(0)
  let page = page_bytes()
  let original : DomainOriginal = { marker: 1, }
  let source = "0123456789012345678901234567890123456789"
  let recipe = Bytes::make(32, 29)
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
    Acquired(value) => value
    Pending(_, _) => abort("original FD not acquired")
  }
  host.claim(original, source, recipe, 1L).unwrap()
  let allocation = host.allocate(original, 24L * page).unwrap()
  let region : @bootstrap.NativeBackedExecutionRegion[
    DomainOriginal,
    DomainChild,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let child : DomainChild = { marker: 1, }
  let foreign : DomainChild = { marker: 1, }
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
      {
        planning_work: 2,
        attempts: 1,
        holdings: 1,
        transfer_bytes: 3L,
        retained_bytes: 0L,
        execution_bytes: 16L * page,
      },
      0L,
      0L,
    )
    .unwrap() {
    Lent(value) => value
    Pending(_, _) => abort("original writer range not lent")
  }
  let view = match host.map_backed_view(original, loan, child, 0).unwrap() {
    Mapped(value) => value
    PendingView(_, _) => abort("original view not mapped")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(value) => value
    DomainPending(_, _) => abort("original domain not acquired")
  }
  require(
    count,
    host.usage().reserved_execution_bytes == 64L * page,
    "domain suballocates one original backing reservation",
  )
  require(
    count,
    host.acquire_backed_domain(original, view, child)
    is Err(Bootstrap(AlreadyConsumed)),
    "same original view cannot create a second domain",
  )
  require(
    count,
    host.close_backed_view(original, view, child)
    is Err(Bootstrap(ReadersPending)),
    "domain custody keeps original outer view pending",
  )
  require(
    count,
    host.transfer_backed_domain(original, domain, foreign)
    is Err(Bootstrap(ForeignOriginal)),
    "foreign child cannot transfer original domain",
  )
  require(
    count,
    host.project_prepared_domain(original, domain, child)
    is Err(Bootstrap(Unavailable)),
    "untransferred original domain cannot produce bootstrap material",
  )
  host.transfer_backed_domain(original, domain, child).unwrap()
  require(
    count,
    host.project_prepared_domain(original, domain, foreign)
    is Err(Bootstrap(ForeignOriginal)),
    "foreign child cannot project original prepared material",
  )
  let material = host.project_prepared_domain(original, domain, child).unwrap()
  let physical = host.project_backed_extent(original, loan, child).unwrap()
  require(
    count,
    material.extent == physical &&
    material.extent.source == source &&
    material.extent.recipe == recipe &&
    material.extent.generation == 1L &&
    material.extent.writable &&
    material.extent.capacity == 64L * page &&
    material.extent.mapping_length == 24L * page &&
    material.extent.payload_offset == page &&
    material.extent.payload_length == 16L * page &&
    material.limits ==
    {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 0L,
      execution_bytes: 16L * page,
    } &&
    host.project_prepared_domain(original, domain, child).unwrap() == material,
    "same checked ticket projects original physical bounds and logical limits without another reserve",
  )
  require(
    count,
    host.transfer_backed_domain(original, domain, child)
    is Err(Bootstrap(AlreadyConsumed)),
    "same domain transfer is one shot",
  )
  host.leave_borrow_scope(original, scope).unwrap()
  host.enter_backed_domain(original, domain, child).unwrap()
  let value = probe(page)
  require(
    count,
    probe_status(value) == 0,
    "same provider allocator observes original domain TLS and live span",
  )
  require(
    count,
    host.close_backed_domain(original, domain, child)
    is Err(Bootstrap(Physical(-3))),
    "active domain scope refuses retirement",
  )
  require(
    count,
    !host.close_backed_region(original, region).unwrap() &&
    host.try_close(original) is Err(ReadersPending),
    "closing original keeps domain view loan and reservation",
  )
  require(
    count,
    host.project_prepared_domain(original, domain, child)
    is Err(Bootstrap(Closing)),
    "cached prepared material still rejects current closing original",
  )
  host.leave_backed_domain(original, domain, child).unwrap()
  require(
    count,
    host.close_backed_domain(original, domain, child)
    is Err(Bootstrap(Physical(-3))),
    "unretired allocation preserves original closing domain",
  )
  require(
    count,
    host.close_backed_domain(original, domain, foreign)
    is Err(Bootstrap(ForeignOriginal)),
    "foreign child cannot retire closing domain",
  )
  require(
    count,
    probe_retire(value) == 0,
    "same provider retires original allocation after scope stops",
  )
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_view(original, view, child).unwrap()
  host.close_backed_view(original, view, child).unwrap()
  // No worker dispatch took place. The exact fixture's physical use stopped
  // and domain/view retirement succeeded; this is not a process-stop inference.
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  require(
    count,
    host.project_prepared_domain(original, domain, child)
    is Err(Bootstrap(Closing)),
    "retired original cannot reissue prepared material or reset its limits",
  )
  require(
    count,
    host.close_backed_view(original, view, child) is Ok(_) &&
    host.close_backed_domain(original, domain, child) is Ok(_) &&
    host.usage().uncertain_transfer_bytes == 3L,
    "closed original aliases remain idempotent after loan backrefs retire",
  )
  require(
    count,
    host.close_backed_region(original, region).unwrap() &&
    host.usage().reserved_execution_bytes == 64L * page,
    "region cleanup does not return original backing",
  )
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
  require(
    count,
    host.usage().reserved_execution_bytes == 0L &&
    host.capacity_usage().allocated == 0L,
    "same Host finally retires original physical backing",
  )
  println(
    "{\"native_domain_cases\":" +
    count.val.to_string() +
    ",\"passed\":" +
    count.val.to_string() +
    ",\"fixture_pages\":64,\"worker\":0,\"vm\":0,\"public_e2e\":0}",
  )
}
