///|
/// The fixture selects disposable 64-page arenas. These are not product limits.
struct BootstrapTestOriginal {
  identity : Int
}

///|
extern "C" fn test_page_bytes_ffi() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn test_supplier(
  original : BootstrapTestOriginal,
  bytes : Int64,
) -> NativeInstalledArenaSupplier[BootstrapTestOriginal] {
  prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
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
}

///|
fn test_host(
  original : BootstrapTestOriginal,
) -> NativeHostBootstrap[BootstrapTestOriginal] {
  let supplier = test_supplier(original, 64L * test_page_bytes_ffi())
  match supplier.acquire(original).unwrap() {
    Acquired(host) => {
      host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
      host
    }
    Pending(_, _) => abort("fixture physical backing unavailable")
  }
}

///|
test "installed supplier refuses foreign original before consuming acquisition" {
  let original = { identity: 1, }
  let foreign = { identity: 1, }
  assert_eq(original.identity, foreign.identity)
  let supplier = test_supplier(original, 64L * test_page_bytes_ffi())
  assert_true(supplier.acquire(foreign) is Err(ForeignOriginal))
  assert_false(supplier.consumed)
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("fixture physical backing unavailable")
  }
  assert_eq(host.usage().reserved_execution_bytes, 64L * test_page_bytes_ffi())
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  // Shared bootstrap capacity is not a dispatched task attempt.
  assert_eq(host.usage().attempts, 0)
}

///|
test "original recipe and generation are fenced before the single transfer" {
  let original = { identity: 2, }
  let supplier = test_supplier(original, 64L * test_page_bytes_ffi())
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("fixture physical backing unavailable")
  }
  assert_true(
    host.claim(original, supplier.source, Bytes::make(32, 18), 1L)
    is Err(ForeignOriginal),
  )
  assert_true(
    host.claim(original, supplier.source, supplier.recipe, 2L)
    is Err(ForeignOriginal),
  )
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let copied_handle = host
  assert_true(
    copied_handle.claim(original, supplier.source, supplier.recipe, 1L)
    is Err(AlreadyConsumed),
  )
  assert_true(supplier.acquire(original) is Err(AlreadyConsumed))
  host.try_close(original).unwrap()
  assert_true(host.allocate(original, 1L) is Err(Closing))
}

///|
test "failed physical acquisition returns the original reserved partial carrier" {
  let original = { identity: 3, }
  let bytes = 64L * test_page_bytes_ffi() + 1L
  let supplier = test_supplier(original, bytes)
  let host = match supplier.acquire(original).unwrap() {
    Pending(host, Physical(-1)) => host
    _ => abort("unaligned acquisition must be a physical rejection")
  }
  assert_eq(host.usage().reserved_execution_bytes, bytes)
  assert_true(
    host.claim(original, supplier.source, supplier.recipe, 1L)
    is Err(Unavailable),
  )
  assert_true(supplier.acquire(original) is Err(AlreadyConsumed))
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_eq(host.usage().attempts, 0)
  host.try_close(original).unwrap()
  assert_eq(host.usage().attempts, 0)
}

///|
test "borrow blocks physical retirement and preserves other original allocations" {
  let original = { identity: 4, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let control = host.capacity_usage().allocated
  let first = host.allocate(original, 1L).unwrap()
  let second = host.allocate(original, page + 1L).unwrap()
  assert_eq(host.capacity_usage().allocated, control + 3L * page)
  let borrowed = host.borrow(original, first).unwrap()
  assert_true(host.retire(original, first) is Err(ReadersPending))
  assert_eq(host.capacity_usage().allocated, control + 3L * page)
  assert_true(
    host.borrow(original, first) is Err(Resource(@resources.ClosedHolding)),
  )
  host.return_borrow(original, borrowed).unwrap()
  assert_true(host.return_borrow(original, borrowed) is Err(AlreadyConsumed))
  host.retire(original, first).unwrap()
  assert_eq(host.capacity_usage().allocated, control + 2L * page)
  assert_false(second.released)
  host.retire(original, first).unwrap()
  assert_eq(host.capacity_usage().allocated, control + 2L * page)
  host.try_close(original).unwrap()
  assert_true(second.released)
  assert_eq(host.capacity_usage().allocated, 0L)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}

///|
test "close pending keeps the same backing and settles only after original reader stop" {
  let original = { identity: 5, }
  let host = test_host(original)
  let child = host.allocate(original, 1L).unwrap()
  let borrowed = host.borrow(original, child).unwrap()
  assert_true(host.try_close(original) is Err(ReadersPending))
  assert_false(host.physical_closed)
  assert_false(host.closed)
  assert_eq(host.usage().reserved_execution_bytes, 64L * test_page_bytes_ffi())
  assert_true(host.allocate(original, 1L) is Err(Closing))
  host.return_borrow(original, borrowed).unwrap()
  host.try_close(original).unwrap()
  assert_true(host.physical_closed)
  assert_true(host.closed)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}

///|
test "Common delegation reports are cumulative and unknown final usage is not refunded" {
  let original = { identity: 6, }
  let host = test_host(original)
  let child = host
    .delegate(original, {
      planning_work: 4,
      attempts: 2,
      holdings: 1,
      transfer_bytes: 12L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    })
    .unwrap()
  let usage : @resources.LedgerUsage = {
    planning_work: 2,
    attempts: 1,
    reserved_attempts: 0,
    live_reservations: 0,
    live_delegations: 0,
    holdings: 0,
    transferred_bytes: 7L,
    uncertain_transfer_bytes: 0L,
    reserved_transfer_bytes: 5L,
    held_bytes: 0L,
    reserved_retention_bytes: 0L,
    reserved_execution_bytes: 0L,
    peak_retention_bytes: 0L,
  }
  host.report(original, child, usage).unwrap()
  host.report(original, child, usage).unwrap()
  assert_eq(host.usage().transferred_bytes, 7L)
  assert_eq(host.usage().planning_work, 2)
  assert_true(
    host.report(original, child, { ..usage, transferred_bytes: 6L, })
    is Err(Resource(@resources.InvalidCharge)),
  )
  assert_true(
    host.delegate(original, {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 1L,
    })
    is Err(Unavailable),
  )
  host.try_close(original).unwrap()
  assert_eq(host.usage().transferred_bytes, 7L)
  assert_eq(host.usage().uncertain_transfer_bytes, 5L)
  assert_eq(host.usage().planning_work, 4)
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}
