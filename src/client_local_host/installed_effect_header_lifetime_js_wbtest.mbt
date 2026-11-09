///|
test "HTTP selected header output preserves all original peak work and returned pair storage" {
  for header_bytes in [1, 32, 16384, 2147483647] {
    let h = header_bytes.to_int64()
    // H two-element pairs and one H-element outer Array. Use the shared
    // constructor owner, without another coefficient or a copied JS cap.
    let arrays = @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: h + 1L,
      reference_items: 3L * h,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    }).unwrap()
    let output : @execution.PreparationRepresentationUnits = {
      record_headers: arrays.record_headers,
      reference_slots: arrays.reference_slots,
      scalar_words: arrays.scalar_words,
      owned_utf16_units: 20L * h,
      owned_wire_bytes: 0L,
    }
    let body = installed_effect_response_buffer_construction_capacity(
      524288,
      response_read_quantum=16384,
    ).unwrap()
    let old_headers = installed_effect_response_headers_representation(
      header_bytes,
    ).unwrap()
    let actual = installed_effect_http_response_construction_capacity(
      524288,
      header_bytes,
      response_read_quantum=16384,
    ).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(actual),
      2L * @execution.execution_capacity_retained_bytes(body) +
      @execution.preparation_representation_cost(output).unwrap(),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(actual),
      @execution.execution_capacity_execution_bytes(body) +
      @execution.preparation_representation_cost(old_headers).unwrap(),
    )
    assert_true(
      @execution.preparation_representation_cost(output).unwrap() <
      @execution.preparation_representation_cost(old_headers).unwrap(),
    )
  }
}

///|
test "HTTP header full peak and returned output each reject one byte short on the real Ledger" {
  let capacity = installed_effect_http_response_construction_capacity(
    524288,
    16384,
    response_read_quantum=16384,
  ).unwrap()
  let r = @execution.execution_capacity_retained_bytes(capacity)
  let e = @execution.execution_capacity_execution_bytes(capacity)
  let limits : @resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 1L,
    retained_bytes: r,
    execution_bytes: e,
  }
  let short_output = @resources.create_ledger({
    ..limits,
    retained_bytes: r - 1L,
  }).unwrap()
  let before = @resources.ledger_usage(short_output)
  assert_true(
    @resources.reserve_attempt(short_output, 1L, r, e) is Err(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(short_output), before)
  let short_peak = @resources.create_ledger({
    ..limits,
    execution_bytes: e - 1L,
  }).unwrap()
  let before = @resources.ledger_usage(short_peak)
  assert_true(
    @resources.reserve_attempt(short_peak, 1L, r, e) is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(short_peak), before)
  let ledger = @resources.create_ledger(limits).unwrap()
  let token = @resources.reserve_attempt(ledger, 1L, r, e).unwrap()
  let before = @resources.ledger_usage(ledger)
  // A failed/pending constructor never reaches projection-complete. Its
  // original E peak remains reserved; a logical failure is not disposal.
  @resources.mark_cleanup_pending(ledger, token).unwrap()
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, token).unwrap(),
    (r, e),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.settle_reservation(ledger, token).unwrap()
}

///|
test "HTTP completed header workspace returns on its same physical token without cleanup ACK" {
  let capacity = installed_effect_http_response_construction_capacity(
    524288,
    16384,
    response_read_quantum=16384,
  ).unwrap()
  let r = @execution.execution_capacity_retained_bytes(capacity)
  let e = @execution.execution_capacity_execution_bytes(capacity)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(capacity),
    parent_limit=Some(536870912L),
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  begin_installed_effect_operation_input(
    child,
    prepare_installed_effect_operation_extent("send", capacity, 7L, true).unwrap(),
  ).unwrap()
  guard child.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(token)) else {
    fail("original physical token missing")
  }
  @resources.mark_cleanup_pending(ledger, token).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, token).unwrap(),
    (r, e),
  )
  complete_installed_effect_operation_response_projection(child).unwrap()
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, token).unwrap(),
    (r, r),
  )
  assert_eq(@resources.ledger_usage(ledger), {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - (e - r),
  })
  assert_true(@resources.reservation_open(token))
  assert_true(@resources.reservation_pending(token))
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}
