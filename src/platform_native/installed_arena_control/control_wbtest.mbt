///|
// Prepared type/conformance input only. These use the non-test Host anchor;
// their 64-page mappings are fixture selections, not installed product limits.
extern "C" fn page_bytes_ffi() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn prepared_host(bytes : Int64) -> InstalledArenaHost {
  prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17), 1L, bytes,
    { planning_work: 20, attempts: 8, holdings: 4,
      transfer_bytes: 30L, retained_bytes: 0L, execution_bytes: bytes, },
    65536L,
  ).unwrap()
}

///|
test "installed Host intent is unavailable until its original acquisition and claim" {
  let host = prepared_host(64L * page_bytes_ffi())
  assert_true(host.require_current() is Err(@bootstrap.Unavailable))
  host.acquire().unwrap()
  host.require_current().unwrap()
  let copied_reference = host
  assert_true(copied_reference.acquire() is Err(@bootstrap.AlreadyConsumed))
  host.try_close().unwrap()
  assert_true(host.require_current() is Err(@bootstrap.Closing))
}

///|
test "partial installed acquisition keeps its original primary issue and cleanup carrier" {
  let host = prepared_host(64L * page_bytes_ffi() + 1L)
  assert_true(host.acquire() is Err(@bootstrap.Physical(-1)))
  assert_eq(host.acquisition_issue(), Some(@bootstrap.Physical(-1)))
  assert_true(host.backing is Some(_))
  assert_true(host.require_current() is Err(@bootstrap.Physical(-1)))
  assert_true(host.acquire() is Err(@bootstrap.AlreadyConsumed))
  host.try_close().unwrap()
  assert_eq(host.acquisition_issue(), Some(@bootstrap.Physical(-1)))
  assert_true(host.backing is None)
  host.try_close().unwrap()
}

///|
test "matching metadata cannot transfer another installed Host allocation or borrower" {
  let first = prepared_host(64L * page_bytes_ffi())
  let second = prepared_host(64L * page_bytes_ffi())
  first.acquire().unwrap()
  second.acquire().unwrap()
  let allocation = first.allocate(1L).unwrap()
  let borrow = first.borrow(allocation).unwrap()
  assert_true(second.borrow(allocation) is Err(@bootstrap.ForeignOriginal))
  assert_true(second.retire(allocation) is Err(@bootstrap.ForeignOriginal))
  assert_true(second.return_borrow(borrow) is Err(@bootstrap.ForeignOriginal))
  first.return_borrow(borrow).unwrap()
  first.try_close().unwrap()
  second.try_close().unwrap()
}

///|
test "pending installed close retains original references until the same reader returns" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  let allocation = host.allocate(1L).unwrap()
  let borrow = host.borrow(allocation).unwrap()
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_false(host.closed)
  assert_true(host.backing is Some(_))
  assert_true(host.require_current() is Err(@bootstrap.Closing))
  assert_true(host.allocate(1L) is Err(@bootstrap.Closing))
  host.return_borrow(borrow).unwrap()
  host.try_close().unwrap()
  assert_true(host.closed)
  assert_true(host.backing is None)
  assert_true(host.supplier is None)
}

///|
test "installed arena does not manufacture an unrelated worker byte delegation" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  assert_true(host.delegate(
    { planning_work: 0, attempts: 0, holdings: 0, transfer_bytes: 0L,
      retained_bytes: 0L, execution_bytes: 1L, },
  ) is Err(@bootstrap.Unavailable))
  host.try_close().unwrap()
}
