///|
/// Explicit diagnostic original, never an installed product supplier or grant.
struct ConformanceOriginal {
  marker : Int
}

///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(condition : Bool, name : String) -> Unit {
  if !condition {
    abort("original FD conformance failed: " + name)
  }
}

///|
/// The diagnostic launcher supplies one exact private 64-page regular FD as
/// stdin. This package neither creates an FD nor opens a worker/VM/Run. Its
/// declared fixture envelope is not a numerical installed product profile.
fn main {
  let page = page_bytes()
  let bytes = page * 64L
  let original : ConformanceOriginal = { marker: 1, }
  // Matching original metadata is not the same physical supplier reference.
  let foreign_original : ConformanceOriginal = { marker: original.marker, }
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
    Pending(_, _) => abort("original private FD was not acquired")
  }
  require(
    host.usage().reserved_execution_bytes == bytes &&
    host.require_current(foreign_original) is Err(ForeignOriginal),
    "one original full reservation",
  )
  require(
    supplier.acquire_fd(original, 0) is Err(AlreadyConsumed),
    "same intent cannot reserve again",
  )
  host.claim(original, source, recipe, 1L).unwrap()
  host.require_current(original).unwrap()
  let control = host.capacity_usage().allocated
  let allocation = host.allocate(original, page + 1L).unwrap()
  require(
    control > 0L &&
    host.capacity_usage().allocated == control + 2L * page &&
    host.usage().reserved_execution_bytes == bytes,
    "rounded allocation suballocates original backing",
  )
  let loan = host.borrow(original, allocation).unwrap()
  host.enter_borrow_scope(original, loan).unwrap()
  require(
    host.try_close(original) is Err(ReadersPending) &&
    host.usage().reserved_execution_bytes == bytes &&
    host.allocate(original, page) is Err(Closing),
    "closing keeps original held while the same scope is live",
  )
  host.leave_borrow_scope(original, loan).unwrap()
  require(
    host.try_close(original) is Err(ReadersPending) &&
    host.usage().reserved_execution_bytes == bytes,
    "leaving a scope does not return its original loan",
  )
  host.return_borrow(original, loan).unwrap()
  require(
    host.return_borrow(original, loan) is Err(AlreadyConsumed),
    "same loan cannot return twice",
  )
  host.try_close(original).unwrap()
  require(
    host.capacity_usage().allocated == 0L &&
    host.usage().reserved_execution_bytes == 0L,
    "physical cleanup settles the same original capacity",
  )
  host.try_close(original).unwrap()
  require(
    host.usage().attempts == 1,
    "successful double close consumes no new attempt",
  )
  println(
    "{\"native_fd_owner_cases\":8,\"passed\":8,\"fixture_pages\":64,\"vm\":0,\"public_e2e\":0}",
  )
}
