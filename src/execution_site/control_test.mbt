///|
fn test_site(key : String) -> ExecutionSite {
  create_site(key, 1, "test-runtime/1", 1, 1, 100L, 100L).unwrap()
}

///|
test "operation capacity, holding, and teardown have one portable authority" {
  let site = test_site("site")
  let operation = start_site_operation(site, 8L, 3L).unwrap()
  assert_eq(site_status(site), [1L, 0L, 1L, 0L, 0L, 0L, 0L, 8L, 3L, 8L, 0L])
  assert_true(start_site_operation(site, 1L, 1L) is None)
  let holding = retain_site_operation_holding(operation, 7L).unwrap()
  assert_eq(settle_site_operation(operation), true)
  assert_eq(site_status(site), [1L, 0L, 0L, 0L, 1L, 0L, 7L, 0L, 0L, 8L, 0L])
  begin_site_teardown(site)
  assert_eq(site_status(site)[10], 0L)
  assert_eq(release_site_holding(holding), true)
  assert_eq(site_status(site)[10], 1L)
}

///|
test "Transfer stops source and destination independently" {
  let source = test_site("source")
  let destination = test_site("destination")
  let transfer = start_site_transfer(source, destination, 9L, 4L).unwrap()
  assert_eq(site_status(source)[3], 1L)
  assert_eq(site_status(destination)[3], 1L)
  assert_eq(settle_site_transfer_source(transfer), true)
  assert_eq(site_status(source)[3], 0L)
  assert_eq(site_status(destination)[3], 1L)
  let holding = retain_site_transfer_holding(transfer, 6L).unwrap()
  assert_eq(settle_site_transfer_destination(transfer), true)
  assert_eq(site_status(destination)[3], 0L)
  assert_eq(site_status(destination)[6], 6L)
  assert_eq(release_site_holding(holding), true)
}

///|
test "forced loss invalidates unfinished work without refunding holdings" {
  let source = test_site("source")
  let destination = test_site("destination")
  let transfer = start_site_transfer(source, destination, 9L, 4L).unwrap()
  revoke_site(source)
  assert_eq(site_transfer_available(transfer), false)
  assert_true(retain_site_transfer_holding(transfer, 6L) is None)
  assert_eq(site_status(destination)[7], 9L)
  settle_site_transfer_source(transfer) |> ignore
  settle_site_transfer_destination(transfer) |> ignore
  assert_eq(site_status(destination)[7], 0L)
}

///|
test "cleanup responsibility is independent from operation stop" {
  let site = test_site("site")
  let cleanup = retain_site_cleanup(site)
  begin_site_teardown(site)
  assert_eq(site_status(site)[10], 0L)
  assert_eq(release_site_cleanup(cleanup), true)
  assert_eq(site_status(site)[10], 1L)
}
