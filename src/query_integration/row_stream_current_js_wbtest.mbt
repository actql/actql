///|
test "response attempt refuses current callback closure without refunding its original debit" {
  let current_action : Ref[(() -> Unit)?] = Ref(None)
  let prepared_original = Ref(1)
  let root = cleanup_original_root(
    cleanup_create_loader(cleanup_test_url()),
    prepared_original,
    () => if current_action.val is Some(action) { action() },
  )
  let admission = @resources.prepare_node_managed_run_admission(
    root, prepared_original,
  ).unwrap()
  let ledger = @resources.start_node_managed_run_admission(admission).unwrap()
  let before = @resources.ledger_usage(ledger)
  let (_, acquisition) = row_page_acquisition()
  let run = provider_capacity_start(acquisition, ledger, "stream-current-start")
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let response = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(response, () => true).unwrap()
  let calls = Ref(0)
  current_action.val = Some(() => {
    // Reenter the actual original Resource current fence once. Logical close
    // invalidates this response but does not settle its physical reservation.
    current_action.val = None
    calls.val += 1
    @row_host.close_row_run(run)
  })
  assert_true(
    @row_host.begin_row_run_response_attempt(response) is Err(InvalidState),
  )
  assert_eq(calls.val, 1)
  let spent = @resources.ledger_usage(ledger)
  assert_eq(spent.attempts, before.attempts + 1)
  assert_eq(spent.reserved_attempts, before.reserved_attempts)
  assert_eq(spent.transferred_bytes, before.transferred_bytes)
  assert_true(
    @row_host.check_row_run_response_borrow_current(response)
    is Err(InvalidState),
  )
  assert_true(
    @row_host.begin_row_run_response_attempt(response) is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), spent)
  @row_host.close_accounted_row_run(run).unwrap()
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed, {
    ..before,
    attempts: before.attempts + 1,
    peak_retention_bytes: spent.peak_retention_bytes,
  })
  @resources.cleanup_node_managed_run_admission(admission).unwrap()
  assert_eq(@resources.ledger_usage(ledger), closed)
}

///|
test "stream append refuses current callback closure while retaining actual received bytes" {
  let current_action : Ref[(() -> Unit)?] = Ref(None)
  let prepared_original = Ref(1)
  let root = cleanup_original_root(
    cleanup_create_loader(cleanup_test_url()),
    prepared_original,
    () => if current_action.val is Some(action) { action() },
  )
  let admission = @resources.prepare_node_managed_run_admission(
    root, prepared_original,
  ).unwrap()
  let ledger = @resources.start_node_managed_run_admission(admission).unwrap()
  let before = @resources.ledger_usage(ledger)
  let (_, acquisition) = row_page_acquisition()
  let run = provider_capacity_start(
    acquisition, ledger, "stream-current-append",
  )
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let response = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(response, () => true).unwrap()
  @row_host.begin_row_run_response_attempt(response).unwrap()
  let ticket = @row_host.charge_row_run_page(run, b"abc").unwrap()
  let calls = Ref(0)
  current_action.val = Some(() => {
    current_action.val = None
    calls.val += 1
    // The original pending ticket is consumed by this logical close. The
    // already received second chunk must still be charged, never readmitted.
    @row_host.close_row_run(run)
  })
  assert_true(
    @row_host.extend_row_run_page_charge(run, ticket, b"def")
    is Err(InvalidState),
  )
  assert_eq(calls.val, 1)
  let spent = @resources.ledger_usage(ledger)
  assert_eq(spent.attempts, before.attempts + 1)
  assert_eq(spent.transferred_bytes, before.transferred_bytes + 6L)
  assert_true(
    @row_host.consume_row_run_observation_charge(run, ticket)
    is Err(InvalidState),
  )
  assert_true(
    @row_host.extend_row_run_page_charge(run, ticket, b"g") is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), spent)
  @row_host.close_accounted_row_run(run).unwrap()
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed, {
    ..before,
    attempts: before.attempts + 1,
    transferred_bytes: before.transferred_bytes + 6L,
    peak_retention_bytes: spent.peak_retention_bytes,
  })
  @resources.cleanup_node_managed_run_admission(admission).unwrap()
  assert_eq(@resources.ledger_usage(ledger), closed)
}
