///|
fn whole_response_growth_start(
  selected : @row_host.RowInputAcquisition,
  retained_extra : Int64,
  execution_extra : Int64,
) -> (@row_host.RowRun, @resources.Ledger) {
  let provider = @execution.execution_capacity(7L, 9L)
  let capacity = @row_host.row_input_acquisition_capacity(selected, provider).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 20000L,
    retained_bytes: @execution.execution_capacity_retained_bytes(capacity) +
    retained_extra,
    execution_bytes: @execution.execution_capacity_execution_bytes(capacity) +
    20000L +
    execution_extra,
  }).unwrap()
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    provider,
    "whole-response-growth",
    _ => true,
    ledger,
    20000L,
    20000L,
  ).unwrap()
  @row_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 20000, max_nodes: 10000, max_depth: 20, max_rows: 128, },
    128,
  ).unwrap()
  (run, ledger)
}

///|
test "WholeInput response growth keeps the original selection charge and cleanup" {
  let (_, _, selected) = whole_row_selection()
  let (_, _, foreign) = whole_row_selection()
  let (run, ledger) = whole_response_growth_start(selected, 20L, 20L)
  assert_true(
    @row_host.borrow_row_input_run_responses(run, foreign) is Err(InvalidState),
  )
  let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  assert_true(@row_host.row_run_response_selection(borrow) is Err(InvalidState))
  let stopped = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  let original = @row_host.row_run_response_selection(borrow).unwrap()
  guard original is @row_host.InputResponse(actual) else {
    fail("original WholeInput selection required")
  }
  assert_true(physical_equal(actual, selected))
  assert_true(
    physical_equal(
      original,
      @row_host.row_run_response_selection(borrow).unwrap(),
    ),
  )
  let capacity = @execution.execution_capacity(11L, 23L).unwrap()
  assert_true(
    @row_host.grow_row_run_response_capacity(borrow, capacity)
    is Err(InvalidState),
  )
  let body = @utf8.encode("[{\"id\":1}]")
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
      @execution.execution_capacity(10L, 23L).unwrap(),
    )
    is Err(Physical(InvalidCharge)),
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
  assert_true(@row_host.row_run_response_selection(borrow) is Err(InvalidState))
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_true(
    @row_host.grow_row_run_response_capacity(borrow, capacity)
    is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
}

///|
test "WholeInput response growth refuses one short byte dimension atomically" {
  let (_, _, selected) = whole_row_selection()
  for dimension in 0..<2 {
    let (run, ledger) = whole_response_growth_start(
      selected,
      if dimension == 0 {
        3L
      } else {
        4L
      },
      if dimension == 1 {
        13L
      } else {
        14L
      },
    )
    let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true).unwrap()
    let body = @utf8.encode("[{\"id\":1}]")
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = @row_host.grow_row_run_response_capacity(
      borrow,
      @execution.execution_capacity(11L, 23L).unwrap(),
    )
    assert_true(
      if dimension == 0 {
        result is Err(Physical(RetentionLimit))
      } else {
        result is Err(Physical(ExecutionLimit))
      },
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    // Refusal consumes neither the charge nor the original borrow.
    assert_true(
      @row_host.row_run_response_selection(borrow)
      is Ok(@row_host.InputResponse(_)),
    )
    @row_host.consume_row_run_response_charge(run, charge).unwrap()
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}
