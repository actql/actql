///|
test "provider next response funds serial bounded units not five future pages" {
  let (_, acquisition) = row_page_acquisition()
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 32768L,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition) +
    7L,
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    137L,
  }).unwrap()
  let run = @row_host.start_accounted_provider_row_acquisition(
    acquisition,
    @execution.execution_capacity(7L, 9L),
    "next-unit",
    _ => true,
    ledger,
    0L,
    128L,
  ).unwrap()
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  assert_true(
    @row_host.ensure_row_run_response_transfer_capacity(borrow, 8192L)
    is Err(InvalidState),
  )
  let stopped = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  for _ in 0..<5 {
    @row_host.ensure_row_run_response_transfer_capacity(borrow, 8192L).unwrap()
    let charge = @row_host.charge_row_run_response_body(run, b"abc").unwrap()
    assert_true(
      @row_host.ensure_row_run_response_transfer_capacity(borrow, 8192L)
      is Err(InvalidState),
    )
    @row_host.consume_row_run_response_charge(run, charge).unwrap()
  }
  let spent = @resources.ledger_usage(ledger)
  assert_eq(spent.attempts, 1)
  assert_eq(spent.transferred_bytes, 15L)
  assert_eq(spent.reserved_transfer_bytes, 8189L)
  assert_true(
    @row_host.ensure_row_run_response_transfer_capacity(borrow, 32754L)
    is Err(Physical(TransferLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), spent)
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_transfer_bytes, 8189L)
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.transferred_bytes, 15L)
  assert_eq(closed.reserved_transfer_bytes, 0L)
  assert_true(
    @row_host.ensure_row_run_response_transfer_capacity(borrow, 8192L)
    is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), closed)
}
