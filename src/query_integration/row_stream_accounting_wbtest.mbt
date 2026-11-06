///|
test "stream chunks extend one original ticket and cancellation never refunds received bytes" {
  let (run, ledger, _) = row_page_run("stream-prefix")
  let ticket = @row_host.charge_row_run_page(run, b"abc").unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 3L)
  @row_host.extend_row_run_page_charge(run, ticket, b"def").unwrap()
  @row_host.extend_row_run_page_charge(run, ticket, b"").unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 6L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  @row_host.close_accounted_row_run(run).unwrap()
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.transferred_bytes, 6L)
  assert_eq(closed.reserved_transfer_bytes, 0L)
  assert_true(
    @row_host.extend_row_run_page_charge(run, ticket, b"g") is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), closed)
}

///|
test "foreign stream ticket cannot charge another run or invalidate its original" {
  let (owner, ledger, _) = row_page_run("stream-owner")
  let (foreign, other, _) = row_page_run("stream-foreign")
  let ticket = @row_host.charge_row_run_page(owner, b"abc").unwrap()
  assert_true(
    @row_host.extend_row_run_page_charge(foreign, ticket, b"d")
    is Err(Physical(ForeignOwner)),
  )
  assert_eq(@resources.ledger_usage(other).transferred_bytes, 0L)
  @row_host.close_accounted_row_run(foreign).unwrap()
  @row_host.extend_row_run_page_charge(owner, ticket, b"d").unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 4L)
  @row_host.consume_row_run_observation_charge(owner, ticket).unwrap()
  @row_host.close_accounted_row_run(owner).unwrap()
}

///|
test "consumed stream ticket cannot append bytes or replace the current ticket" {
  let (run, ledger, _) = row_page_run("stream-replay")
  let previous = @row_host.charge_row_run_page(run, b"abc").unwrap()
  @row_host.consume_row_run_observation_charge(run, previous).unwrap()
  @row_host.charge_row_run_page(run, b"def").unwrap() |> ignore
  assert_true(
    @row_host.extend_row_run_page_charge(run, previous, b"g")
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 6L)
  row_page_assert_closed(run, ledger)
}

///|
test "cumulative stream page overflow charges actual bytes then stops the same attempt" {
  let (run, ledger, _) = row_page_run("stream-page-bound", max_page_bytes=3)
  let ticket = @row_host.charge_row_run_page(run, b"ab").unwrap()
  assert_true(
    @row_host.extend_row_run_page_charge(run, ticket, b"cd")
    is Err(Source(InvalidPage)),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 4L)
  row_page_assert_closed(run, ledger)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 4L)
}

///|
test "stream append cannot exceed the original transfer reservation" {
  let (run, ledger, _) = row_page_run(
    "stream-transfer-bound",
    transfer_bytes=3L,
  )
  let ticket = @row_host.charge_row_run_page(run, b"ab").unwrap()
  assert_true(
    @row_host.extend_row_run_page_charge(run, ticket, b"cd")
    is Err(Physical(TransferLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 2L)
  row_page_assert_closed(run, ledger)
}

///|
test "provider attempt is spent before zero-byte I/O and pending cleanup keeps its original" {
  let (_, acquisition) = row_page_acquisition()
  let ledger = provider_capacity_ledger(acquisition)
  let run = provider_capacity_start(acquisition, ledger, "stream-zero-byte")
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let response = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  assert_true(
    @row_host.begin_row_run_response_attempt(response)
    is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let stopped = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(response, () => stopped.val).unwrap()
  @row_host.begin_row_run_response_attempt(response).unwrap()
  @row_host.begin_row_run_response_attempt(response).unwrap()
  let spent = @resources.ledger_usage(ledger)
  assert_eq(spent.attempts, 1)
  assert_eq(spent.reserved_attempts, 0)
  assert_eq(spent.transferred_bytes, 0L)
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.attempts, 1)
  assert_eq(closed.reserved_attempts, 0)
  assert_eq(closed.transferred_bytes, 0L)
  assert_eq(closed.reserved_transfer_bytes, 0L)
  assert_true(
    @row_host.begin_row_run_response_attempt(response) is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), closed)
}
