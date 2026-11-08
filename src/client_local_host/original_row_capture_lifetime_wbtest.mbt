///|
// Actual common Row capture and original resource read lifecycle. Transport is
// a deterministic fixture acknowledgement, not an installed Source read or a
// Model send grant. All expected values below are independently authored.
test "original Source capture remains held beside the same Scope read until both children clean up" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
  )
  let requirement = original_row_requirement(prepared)
  let acquisition = original_row_acquisition_fixture(requirement)
  let retention = @row_source_host.row_acquisition_retained_capacity(
    acquisition,
  )
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  // The two original unqualified names need an allowance for two 16-byte
  // Array headers and up to four 8-byte backing references, beside the
  // unchanged wires and original-read allowance.
  let record_names = 2L * 16L + 4L * 8L
  assert_eq(retention, 26404096L + record_names)
  let page = @utf8.encode(
    "[{\"id\":2,\"amount\":null},{\"id\":1,\"amount\":7}]",
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes: page.length().to_int64(),
    retained_bytes: retention + 3L + 7L,
    execution_bytes: execution + 128L + 2L + 5L,
  }).unwrap()
  // Only the existing Row allowance and independent census/read fixture
  // amounts are used. This is not an adopted Node wholephysical profile.
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  let settled = Ref(false)
  let run = start_client_original_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    acquisition,
    "original-capture-lifetime",
    _ => settled.val,
    page.length().to_int64(),
    128L,
  ).unwrap()
  @row_source_host.begin_row_run(run, 128, 2, 2).unwrap()
  assert_eq(@row_source_host.accept_row_run_page(run, page).unwrap(), 2)
  @row_source_host.finish_row_run(run).unwrap()
  // Completing page admission is not a physical transport acknowledgement.
  assert_true(
    @row_source_host.begin_row_capture(run)
    is Err(@row_source_host.Evidence(@row_source_host.UnverifiedTransport)),
  )
  settled.val = true
  @row_source_host.begin_row_capture(run).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 7).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  let source = @row_source_host.row_capture_source(capture).unwrap()
  assert_eq(@query.captured_source_row_count(source), Some(2))
  let original = @row_source_host.row_capture_original_read(capture).unwrap()
  let columns = @row_source_host.row_acquisition_columns(acquisition)
  let id = columns.search("id").unwrap()
  let amount = columns.search("amount").unwrap()
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, id)
    is Some(@admitted.Number(2)),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 1, id)
    is Some(@admitted.Number(1)),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, amount)
    is Some(@admitted.Null),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 1, amount)
    is Some(@admitted.Number(7)),
  )
  let captured = @resources.ledger_usage(ledger)
  assert_eq(captured.attempts, 1)
  assert_eq(captured.holdings, 1)
  // Independently authored canonical scan and output are each the 44-byte
  // [{"amount":null,"id":2},{"amount":7,"id":1}]. Keep both wires plus the
  // existing 22404096-unit original read/export allowance, not only 88 bytes.
  assert_eq(captured.held_bytes, 22404184L)
  assert_eq(captured.transferred_bytes, page.length().to_int64())
  assert_eq(captured.reserved_retention_bytes, 3L)
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, captured.held_bytes)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, requirement,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    @publication_host.settle_client_model_read(read, false)
    is Err(@publication_host.Resource(@resources.CleanupPending)),
  )
  let pending = @resources.ledger_usage(ledger)
  assert_eq(pending.held_bytes, 22404184L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  // Total 26404106 + record_names minus the Source holding 22404184 and
  // two live read reservations (3 + 7) leaves 3999912 + record_names.
  // One more must fail without changing usage/serial/custody.
  assert_true(
    @resources.reserve_capacity(ledger, 3999913L + record_names, 0L)
    is Err(@resources.RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), pending)
  assert_true(
    @publication_host.settle_client_model_read(read, false)
    is Err(@publication_host.Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), pending)
  assert_true(@execution.supplied_relation_read_available(original))
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, amount)
    is Some(@admitted.Null),
  )
  assert_true(@resources.capacity_reservation_open(bootstrap))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 22404184L)
  @publication_host.settle_client_model_read(read, true).unwrap()
  // A read child's successful cleanup cannot return the Source's holding or
  // the original bootstrap. The owning Run still waits for Source cleanup.
  assert_eq(@resources.ledger_usage(ledger).held_bytes, captured.held_bytes)
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(@resources.capacity_reservation_open(bootstrap))
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_false(@execution.supplied_relation_read_available(original))
  assert_true(@execution.supplied_relation_read_cell(original, 0, id) is None)
  assert_true(@row_source_host.row_capture_source(capture) is Err(_))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_false(@resources.capacity_reservation_open(bootstrap))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    page.length().to_int64(),
  )
}
