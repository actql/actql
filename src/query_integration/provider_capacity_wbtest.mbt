///|
test "actual native response grows the original Row reservation before decode and retains failed cleanup" {
  let (_, acquisition) = row_page_acquisition()
  let ledger = provider_capacity_ledger(
    acquisition,
    retained_short=-20L,
    execution_short=-20L,
  )
  let run = provider_capacity_start(acquisition, ledger, "response-growth")
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  let stopped = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  let capacity = @execution.execution_capacity(11L, 23L).unwrap()
  assert_true(
    @row_host.grow_row_run_response_capacity(borrow, capacity)
    is Err(InvalidState),
  )
  let body = row_page_body(2)
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  let before = @resources.ledger_usage(ledger)
  @row_host.grow_row_run_response_capacity(borrow, capacity).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_eq(grown, {
    ..before,
    reserved_retention_bytes: before.reserved_retention_bytes + 4L,
    reserved_execution_bytes: before.reserved_execution_bytes + 14L,
    peak_retention_bytes: before.peak_retention_bytes + 4L,
  })
  @row_host.grow_row_run_response_capacity(borrow, capacity).unwrap()
  assert_eq(@resources.ledger_usage(ledger), grown)
  assert_true(
    @row_host.grow_row_run_response_capacity(
      borrow,
      @execution.execution_capacity(100L, 200L).unwrap(),
    )
    is Err(Physical(RetentionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), grown)
  @row_host.consume_row_run_response_charge(run, charge).unwrap()
  assert_true(
    @row_host.grow_row_run_response_capacity(borrow, capacity)
    is Err(InvalidState),
  )
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    grown.reserved_execution_bytes,
  )
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
}

///|
fn provider_capacity_ledger(
  acquisition : @row_host.RowAcquisition,
  retained_short? : Int64 = 0L,
  execution_short? : Int64 = 0L,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 100,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 1024L,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition) +
    7L -
    retained_short,
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    128L +
    9L -
    execution_short,
  }).unwrap()
}

///|
fn provider_capacity_start(
  acquisition : @row_host.RowAcquisition,
  ledger : @resources.Ledger,
  nonce : String,
) -> @row_host.RowRun {
  @row_host.start_accounted_provider_row_acquisition(
    acquisition,
    @execution.execution_capacity(7L, 9L),
    nonce,
    _ => true,
    ledger,
    1024L,
    128L,
  ).unwrap()
}

///|
test "provider envelope missing and one short refuse before any original attempt" {
  let (_, acquisition) = row_page_acquisition()
  let ledger = provider_capacity_ledger(acquisition)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_host.start_accounted_provider_row_acquisition(
      acquisition,
      None,
      "provider-missing",
      _ => true,
      ledger,
      1024L,
      128L,
    )
    is Err(Physical(InvalidLimits)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  for dimension in 0..<2 {
    let short = provider_capacity_ledger(
      acquisition,
      retained_short=if dimension == 0 { 1L } else { 0L },
      execution_short=if dimension == 1 { 1L } else { 0L },
    )
    let original = @resources.ledger_usage(short)
    let refused = @row_host.start_accounted_provider_row_acquisition(
      acquisition,
      @execution.execution_capacity(7L, 9L),
      "provider-short",
      _ => true,
      short,
      1024L,
      128L,
    )
    assert_true(
      if dimension == 0 {
        refused is Err(Physical(RetentionLimit))
      } else {
        refused is Err(Physical(ExecutionLimit))
      },
    )
    assert_eq(@resources.ledger_usage(short), original)
  }
  let run = provider_capacity_start(acquisition, ledger, "provider-exact")
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
  // No original reader has been borrowed or admitted: no physical debt exists.
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "provider envelope requires the exact reader cleanup binding before pages" {
  let (_, acquisition) = row_page_acquisition()
  let ledger = provider_capacity_ledger(acquisition)
  let run = provider_capacity_start(acquisition, ledger, "provider-bind")
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let (_, foreign) = row_page_acquisition()
  assert_true(
    @row_host.borrow_row_run_responses(run, foreign) is Err(ForeignDeclaration),
  )
  assert_true(
    @row_host.charge_row_run_page(run, row_page_body(2))
    is Err(Evidence(UnverifiedTransport)),
  )
  assert_true(
    @row_host.finish_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  assert_true(
    @row_host.borrow_row_run_responses(run, acquisition) is Err(InvalidState),
  )
  let stopped = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  assert_true(
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true)
    is Err(InvalidState),
  )
  assert_true(@row_host.charge_row_run_page(run, row_page_body(2)) is Ok(_))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "provider envelope survives capture callback completion and repeated pending cleanup" {
  let (declaration, acquisition) = row_page_acquisition()
  let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration,
    acquisition,
    row_page_observation(),
    100,
  ).unwrap()
  let ledger = provider_capacity_ledger(acquisition)
  let run = provider_capacity_start(acquisition, ledger, "provider-capture")
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  let stopped = Ref(false)
  let checks = Ref(0)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => {
    checks.val += 1
    stopped.val
  }).unwrap()
  let body = row_page_body(2)
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  @row_host.accept_charged_row_run_values(
    run,
    charge,
    ["id"],
    row_page_values(body, plan),
  ).unwrap()
  |> ignore
  @row_host.finish_row_run(run).unwrap()
  let capture = @row_host.capture_row_run(run).unwrap()
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  let retained = @resources.ledger_usage(ledger)
  assert_true(retained.reserved_retention_bytes >= 7L)
  assert_eq(
    retained.reserved_execution_bytes,
    @row_host.row_acquisition_execution_capacity(acquisition) + 137L,
  )
  assert_eq(checks.val, 0)
  for _ in 0..<2 {
    assert_true(
      @row_host.close_accounted_row_run(run)
      is Err(Evidence(UnverifiedTransport)),
    )
    assert_eq(@resources.ledger_usage(ledger), retained)
  }
  assert_eq(checks.val, 2)
  assert_true(
    @resources.reserve_capacity(ledger, 0L, 1L) is Err(ExecutionLimit),
  )
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(checks.val, 3)
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(checks.val, 3)
  assert_eq(@resources.ledger_usage(ledger), closed)
  assert_true(@row_host.charge_row_run_page(run, body) is Err(InvalidState))
  assert_true(
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true)
    is Err(InvalidState),
  )
}
