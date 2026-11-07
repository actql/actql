///|
// Actual selected Native runtime only. No stock fallback, copied Ledger,
// synthetic capacity ACK or separate Read can satisfy this same-owner route.
test "same original Native Read acquires its window before resize and constructor then retires" {
  let mib = 1048576L
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    16L * mib,
    {
      planning_work: 64,
      attempts: 16,
      holdings: 16,
      transfer_bytes: mib,
      retained_bytes: 0L,
      execution_bytes: 64L * mib,
    },
    mib,
  ).unwrap_or_else(() => abort("Native Read stage: prepare-host"))
  host.acquire().unwrap_or_else(() => abort("Native Read stage: acquire-host"))
  let scope = host.borrow_backing().unwrap_or_else(() => abort("Native Read stage: borrow-root"))
  host.enter_backing_borrow_scope(scope).unwrap_or_else(() => abort("Native Read stage: enter-root"))
  let domain = match
    host
    .prepare_domain_in_process(
      scope,
      8L * mib,
      {
        planning_work: 32,
        attempts: 8,
        holdings: 8,
        transfer_bytes: mib,
        retained_bytes: 8L * mib,
        execution_bytes: 32L * mib,
      },
      initial_window=Some(4L * mib),
    )
    .unwrap_or_else(() => abort("Native Read stage: prepare-domain")) {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("original domain pending")
  }
  host.transfer_domain(domain).unwrap_or_else(() => abort("Native Read stage: transfer-domain"))
  host.leave_backing_borrow_scope(scope).unwrap_or_else(() => abort("Native Read stage: leave-root"))
  host.return_backing_borrow(scope).unwrap_or_else(() => abort("Native Read stage: return-root"))
  host.prepare_domain_read(domain, execution_ceiling=32L * mib).unwrap_or_else(() => abort("Native Read stage: prepare-read-context"))
  let read = match
    host
    .prepare_domain_original_read(domain, {
      bootstrap_retained: 65536L,
      bootstrap_execution: 65536L,
      workspace_execution: 262144L,
      read_retained: 131072L,
      read_execution: mib,
    })
    .unwrap_or_else(() => abort("Native Read stage: fund-original-read")) {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) => fail("original Read pending")
  }
  let consumer = host
    .prepare_domain_original_read_consumer(read, 65536L, 131072L)
    .unwrap_or_else(() => abort("Native Read stage: claim-consumer"))
  // The minimum consuming quote is not the actual original funded amount.
  assert_eq(consumer.retained_bytes, 131072L)
  assert_eq(consumer.execution_bytes, mib)
  host.enter_domain_original_read_consumer(consumer).unwrap_or_else(() => abort("Native Read stage: enter-consumer"))
  let before = host.observe_domain_inventory(domain).unwrap_or_else(() => abort("Native Read stage: observe-before"))
  let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
  host
  .prepare_domain_original_read_construction(
    read,
    6L * mib,
    8L * mib,
    header + 6L * mib + 1L,
  )
  .unwrap_or_else(() => abort("Native Read stage: acquire-resize-original"))
  let after = host.observe_domain_inventory(domain).unwrap_or_else(() => abort("Native Read stage: observe-after"))
  assert_true(after.capacity_bytes > before.capacity_bytes)
  assert_true(physical_equal(consumer.read, read))
  assert_true(
    domain.original_read is Some(original) && physical_equal(original, read),
  )
  let body = Bytes::make(6 * 1048576, 71)
  assert_eq(body.length(), 6 * 1048576)
  assert_eq(body[body.length() - 1], 71)
  host.leave_domain_original_read_consumer(consumer).unwrap_or_else(() => abort("Native Read stage: leave-consumer"))
  host.close_domain_original_read(read).unwrap_or_else(() => abort("Native Read stage: close-read"))
  assert_true(read.closed && read.consumer is None && read.physical_retired.val)
  host.close_domain_after_owner_ack(domain).unwrap_or_else(() => abort("Native Read stage: close-domain"))
  host.try_close().unwrap_or_else(() => abort("Native Read stage: close-host"))
  assert_true(host.closed && domain.closed)
}
