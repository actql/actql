///|
test "in-process domain retains the actual parent loan through separate child and view ACKs" {
  let original = { identity: 93, }
  let child = { identity: 94, }
  let foreign = { identity: 94, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let allocation = host.allocate(original, 24L * page).unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let loan = match
    host
    .lend_backed_region_in_process(
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
      backed_test_limits(16L * page),
      0L,
      0L,
    )
    .unwrap() {
    Lent(loan) => loan
    Pending(_, _) => abort("original local loan unavailable")
  }
  assert_true(host.project_backed_extent(original, loan, child) is Err(_))
  assert_true(
    host.view_backed_region_in_process(original, loan, foreign) is Err(_),
  )
  let view = match
    host.view_backed_region_in_process(original, loan, child).unwrap() {
    Mapped(view) => view
    PendingView(_, _) => abort("original local view unavailable")
  }
  assert_true(
    host.view_backed_region_in_process(original, loan, child) is Err(_),
  )
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(domain) => domain
    DomainPending(_, _) => abort("original local domain unavailable")
  }
  assert_true(host.close_backed_view(original, view, child) is Err(_))
  assert_true(
    host.settle_backed_region_after_owner_ack(original, loan, child, None)
    is Err(_),
  )
  assert_false(loan.physical_returned)
  host.transfer_backed_domain(original, domain, child).unwrap()
  assert_true(host.project_prepared_domain(original, domain, child) is Err(_))
  host.leave_borrow_scope(original, scope).unwrap()
  host.enter_backed_domain(original, domain, child).unwrap()
  let inventory = host
    .observe_backed_domain_inventory(original, domain, child)
    .unwrap()
  assert_eq(inventory.capacity_bytes, 16L * page)
  assert_eq(inventory.page_bytes, page)
  assert_true(inventory.control_bytes > 0L)
  assert_true(inventory.control_bytes < inventory.capacity_bytes)
  assert_eq(inventory.occupied_bytes, inventory.control_bytes)
  assert_eq(inventory.peak_occupied_bytes, inventory.occupied_bytes)
  assert_true(host.close_backed_domain(original, domain, child) is Err(_))
  host.leave_backed_domain(original, domain, child).unwrap()
  assert_true(host.try_close(original) is Err(ReadersPending))
  assert_false(host.physical_closed)
  host.close_backed_domain(original, domain, child).unwrap()
  assert_false(loan.physical_returned)
  host.close_backed_view(original, view, child).unwrap()
  assert_false(loan.physical_returned)
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(loan.physical_returned && loan.settled)
  assert_true(host.close_backed_region(original, region).unwrap())
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
}
