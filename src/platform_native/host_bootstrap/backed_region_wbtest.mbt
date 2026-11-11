///|
fn backed_test_limits(page : Int64) -> @resources.LedgerLimits {
  {
    planning_work: 2,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 3L,
    retained_bytes: 0L,
    execution_bytes: page,
  }
}

///|
test "backed region retains the original rounded allocation without another byte reserve" {
  let original = { identity: 20, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let control = host.capacity_usage().allocated
  let allocation = host.allocate(original, 1L).unwrap()
  let before = host.usage().reserved_execution_bytes
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  assert_eq(
    @resources.shared_allocation_usage(allocation.allocation).readers,
    1,
  )
  assert_eq(host.usage().reserved_execution_bytes, before)
  assert_true(
    host.borrow(original, allocation) is Err(Resource(@resources.ClosedHolding)),
  )
  assert_true(host.retire(original, allocation) is Err(ReadersPending))
  assert_eq(host.capacity_usage().allocated, control + page)
  assert_true(host.close_backed_region(original, region).unwrap())
  assert_true(host.close_backed_region(original, region).unwrap())
  host.try_close(original).unwrap()
}

///|
test "backed region denies unentered scope and independently unfunded overhead before physical lending" {
  let original = { identity: 21, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let allocation = host.allocate(original, page).unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  let child = { identity: 22, }
  let extent : @resources.BackedExecutionExtent = {
    offset: 0L,
    length: page,
    payload_offset: 0L,
    payload_length: page,
  }
  assert_true(
    host.lend_backed_region(
      original,
      region,
      scope,
      child,
      extent,
      @resources.ExclusiveWrite,
      backed_test_limits(page),
      0L,
      0L,
    )
    is Err(Bootstrap(Unavailable)),
  )
  assert_eq(region.loans.length(), 0)
  host.enter_borrow_scope(original, scope).unwrap()
  assert_true(
    host.lend_backed_region(
      original,
      region,
      scope,
      child,
      extent,
      @resources.ExclusiveWrite,
      backed_test_limits(page),
      0L,
      1L,
    )
    is Err(Accounting(Resource(_))),
  )
  assert_eq(region.loans.length(), 0)
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  host.try_close(original).unwrap()
}

///|
test "failed physical region lend retains the same logical quota and original borrow for cleanup" {
  let original = { identity: 23, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let allocation = host.allocate(original, page).unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let child = { identity: 24, }
  let extent : @resources.BackedExecutionExtent = {
    offset: 0L,
    length: page,
    payload_offset: 0L,
    payload_length: page,
  }
  // Anonymous backing is not an FD region. The original C rejects it;
  // the pending carrier is still the already-reserved Common child ticket.
  let loan = match
    host
    .lend_backed_region(
      original,
      region,
      scope,
      child,
      extent,
      @resources.ExclusiveWrite,
      backed_test_limits(page),
      0L,
      0L,
    )
    .unwrap() {
    Pending(loan, Bootstrap(Physical(-1))) => loan
    _ => abort("anonymous backing must not become a shared FD view")
  }
  assert_eq(region.loans.length(), 1)
  assert_true(physical_equal(region.loans[0], loan))
  let loan_capacity = region.loans.capacity()
  assert_true(loan_capacity > 0)
  assert_true(
    host.close_backed_region({ identity: 23, }, region)
    is Err(Bootstrap(ForeignOriginal)),
  )
  assert_eq(region.loans.length(), 1)
  assert_eq(region.loans.capacity(), loan_capacity)
  assert_true(physical_equal(region.loans[0], loan))
  assert_eq(
    @resources.shared_allocation_usage(allocation.allocation).readers,
    2,
  )
  assert_false(host.close_backed_region(original, region).unwrap())
  assert_eq(region.loans.length(), 1)
  assert_eq(region.loans.capacity(), loan_capacity)
  assert_true(physical_equal(region.loans[0], loan))
  assert_false(loan.physical_returned || loan.settled)
  assert_true(host.try_close(original) is Err(ReadersPending))
  // The negative C lend has never published a view or child. No process
  // termination is inferred for a successfully entered worker here.
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(loan.physical_returned && loan.settled)
  assert_eq(host.usage().uncertain_transfer_bytes, 3L)
  assert_true(host.close_backed_region(original, region).unwrap())
  assert_eq(region.loans.length(), 0)
  // A zero length alone leaves the old Native backing slots and the
  // loan -> region cycle alive. Successful original close must release them.
  assert_eq(region.loans.capacity(), 0)
  assert_true(host.close_backed_region(original, region).unwrap())
  assert_eq(region.loans.length(), 0)
  assert_eq(region.loans.capacity(), 0)
  assert_true(loan.physical_returned && loan.settled)
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
}

///|
test "foreign child cannot return the physical original or settle its same logical reservation" {
  let original = { identity: 25, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let allocation = host.allocate(original, page).unwrap()
  let region : NativeBackedExecutionRegion[
    BootstrapTestOriginal,
    BootstrapTestOriginal,
  ] = host.issue_backed_region(original, allocation).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let child = { identity: 26, }
  let foreign = { identity: 26, }
  let extent : @resources.BackedExecutionExtent = {
    offset: 0L,
    length: page,
    payload_offset: 0L,
    payload_length: page,
  }
  let loan = match
    host
    .lend_backed_region(
      original,
      region,
      scope,
      child,
      extent,
      @resources.ExclusiveWrite,
      backed_test_limits(page),
      0L,
      0L,
    )
    .unwrap() {
    Pending(loan, _) => loan
    _ => abort("anonymous backing is not an FD view")
  }
  assert_true(
    host.settle_backed_region_after_owner_ack(original, loan, foreign, None)
    is Err(Bootstrap(ForeignOriginal)),
  )
  assert_false(loan.physical_returned || loan.settled)
  assert_eq(
    @resources.shared_allocation_usage(allocation.allocation).readers,
    2,
  )
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  assert_true(host.close_backed_region(original, region).unwrap())
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
}
