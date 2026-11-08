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
  let scope = host
    .borrow_backing()
    .unwrap_or_else(() => abort("Native Read stage: borrow-root"))
  host
  .enter_backing_borrow_scope(scope)
  .unwrap_or_else(() => abort("Native Read stage: enter-root"))
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
  host
  .transfer_domain(domain)
  .unwrap_or_else(() => abort("Native Read stage: transfer-domain"))
  host
  .leave_backing_borrow_scope(scope)
  .unwrap_or_else(() => abort("Native Read stage: leave-root"))
  host
  .return_backing_borrow(scope)
  .unwrap_or_else(() => abort("Native Read stage: return-root"))
  host
  .prepare_domain_read(domain, execution_ceiling=32L * mib)
  .unwrap_or_else(() => abort("Native Read stage: prepare-read-context"))
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
  host
  .enter_domain_original_read_consumer(consumer)
  .unwrap_or_else(() => abort("Native Read stage: enter-consumer"))
  let before = host
    .observe_domain_inventory(domain)
    .unwrap_or_else(() => abort("Native Read stage: observe-before"))
  let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
  host
  .prepare_domain_original_read_construction(
    read,
    6L * mib,
    8L * mib,
    header + 6L * mib + 1L,
  )
  .unwrap_or_else(() => abort("Native Read stage: acquire-resize-original"))
  let after = host
    .observe_domain_inventory(domain)
    .unwrap_or_else(() => abort("Native Read stage: observe-after"))
  assert_true(after.capacity_bytes > before.capacity_bytes)
  assert_true(physical_equal(consumer.read, read))
  assert_true(
    domain.original_read is Some(original) && physical_equal(original, read),
  )
  let body = Bytes::make(6 * 1048576, 71)
  assert_eq(body.length(), 6 * 1048576)
  assert_eq(body[body.length() - 1], 71)
  host
  .leave_domain_original_read_consumer(consumer)
  .unwrap_or_else(() => abort("Native Read stage: leave-consumer"))
  match host.close_domain_original_read(read) {
    Ok(_) => ()
    Err(issue) => {
      let family = match issue {
        Domain(@bootstrap.Bootstrap(@bootstrap.Physical(code))) =>
          "physical=" + code.to_string()
        Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)) =>
          "ReadersPending"
        Domain(@bootstrap.Bootstrap(_)) => "bootstrap"
        Domain(@bootstrap.Accounting(_)) => "domain-accounting"
        Child(_) => "child"
        Read(@resources.ChangedOriginalState) => "ChangedOriginalState"
        Read(@resources.CleanupPending) => "CleanupPending"
        Read(@resources.Resource(_)) => "read-resource"
        Read(_) => "read-original"
        Buffer(_) => "buffer"
      }
      println("Native Read close family: " + family)
      match host.observe_domain_original_read_cleanup(read) {
        Err(_) => println("Native Read cleanup observation unavailable")
        Ok(observed) =>
          println(
            "Native Read cleanup blocks=" +
            observed.managed_live_blocks.to_string() +
            " bytes=" +
            observed.managed_requested_bytes.to_string() +
            " min=" +
            observed.minimum_managed_request.to_string() +
            " max=" +
            observed.maximum_managed_request.to_string() +
            " active=" +
            observed.active.to_string() +
            " users=" +
            observed.users.to_string(),
          )
      }
      abort("Native Read stage: close-read")
    }
  }
  assert_true(read.closed && read.consumer is None && read.physical_retired.val)
  host
  .close_domain_after_owner_ack(domain)
  .unwrap_or_else(() => abort("Native Read stage: close-domain"))
  host.try_close().unwrap_or_else(() => abort("Native Read stage: close-host"))
  assert_true(host.closed && domain.closed)
}

///|
fn result_delivery_window_construct(target : Int) -> Unit raise {
  let output = Buffer(size_hint=target)
  for _ in 0..<target {
    output.write_byte(71)
  }
  let bytes = output.to_bytes()
  assert_eq(output.length(), target)
  assert_eq(bytes.length(), target)
  assert_eq(bytes[0], 71)
  assert_eq(bytes[target - 1], 71)
}

///|
test "original Native Read funds delivery backing and copy beside its unchanged input basis" {
  // The existing fresh Source-frame fixture declares this same64-page input.
  let fixture = original_read_consumer_fixture("source-frame-original")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  host.enter_domain_original_read_consumer(consumer).unwrap()
  let target = 16384
  let (retained, execution, contiguous) = @native_client.native_local_result_delivery_window_construction(
    target,
  ).unwrap()
  // Independent fixed Buffer/data/Bytes tariff; no existing row/input amount
  // is replaced by the new window, and the original claim stays the owner.
  assert_eq(retained, 2L * target.to_int64() + 3L * 16L + 8L + 8L)
  assert_eq(execution, retained)
  let initial_retained = consumer.initial_retained_bytes
  let initial_execution = consumer.initial_execution_bytes
  host
  .prepare_domain_original_read_construction(
    fixture.read,
    retained,
    execution,
    contiguous,
  )
  .unwrap()
  assert_eq(consumer.retained_bytes, initial_retained + retained)
  assert_eq(consumer.execution_bytes, initial_execution + execution)
  assert_true(physical_equal(consumer.read, fixture.read))
  let ledger = fixture.read.ledger.unwrap()
  assert_true(
    @resources.ledger_usage(ledger).reserved_retention_bytes >=
    initial_retained + retained,
  )
  assert_true(
    @resources.ledger_usage(ledger).reserved_execution_bytes >=
    initial_execution + execution,
  )
  // The actual constructor follows its successful same-domain geometry entry.
  // Both aliases retire inside this frame before the original Read is closed.
  result_delivery_window_construct(target)
  host.leave_domain_original_read_consumer(consumer).unwrap()
  original_read_consumer_finish(fixture)
}
