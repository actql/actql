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

///|
test "WholeInput announced body reserves the same original before transfer then consumes its actual ticket once" {
  let (_, _, selected) = whole_row_selection()
  // This case also admits an actual page, unlike the separate one-short
  // provider-growth cases. Use the existing whole_row_run fixture's finite
  // 16/32MiB page-construction backing, not a future-input startup allocation.
  let (run, ledger) = whole_response_growth_start(
    selected, 16777216L, 33554432L,
  )
  let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  let capacity = @execution.execution_capacity(11L, 23L).unwrap()
  assert_true(
    @row_host.grow_row_run_response_construction_capacity(borrow, capacity)
    is Err(InvalidState),
  )
  let stopped = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  let before = @resources.ledger_usage(ledger)
  @row_host.grow_row_run_response_construction_capacity(borrow, capacity).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_eq(
    grown.reserved_retention_bytes,
    before.reserved_retention_bytes + 4L,
  )
  assert_eq(
    grown.reserved_execution_bytes,
    before.reserved_execution_bytes + 14L,
  )
  assert_eq(grown.transferred_bytes, 0L)
  assert_true(
    @row_host.row_run_response_selection(borrow)
    is Ok(@row_host.InputResponse(_)),
  )
  let body = @utf8.encode("{\"original_protocol\":true}")
  let charge = @row_host.charge_row_run_response_body(run, body).unwrap()
  assert_true(
    @row_host.grow_row_run_response_construction_capacity(borrow, capacity)
    is Err(InvalidState),
  )
  @row_host.grow_row_run_response_capacity(borrow, capacity).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_page(
      run,
      charge,
      @utf8.encode("[{\"id\":1}]"),
    ).unwrap(),
    1,
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  let admitted = @resources.ledger_usage(ledger)
  assert_true(
    admitted.reserved_retention_bytes >= grown.reserved_retention_bytes,
  )
  assert_true(
    admitted.reserved_execution_bytes >= grown.reserved_execution_bytes,
  )
  assert_true(
    @row_host.consume_row_run_response_charge(run, charge)
    is Err(Physical(InvalidCharge)),
  )
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    admitted.reserved_execution_bytes,
  )
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "WholeInput announced body refuses either short dimension without issuing a charge or changing its original selection" {
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
    let before = @resources.ledger_usage(ledger)
    let result = @row_host.grow_row_run_response_construction_capacity(
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
    assert_true(
      @row_host.row_run_response_selection(borrow)
      is Ok(@row_host.InputResponse(_)),
    )
    // No received-byte charge was issued by the refusing announced-length path.
    let charge = @row_host.charge_row_run_response_body(run, @utf8.encode("{}")).unwrap()
    @row_host.consume_row_run_response_charge(run, charge).unwrap()
    @row_host.close_accounted_row_run(run).unwrap()
  }
}

///|
test "WholeInput completed provider returns only workspace while its original input stays live" {
  let (_, _, selected) = whole_row_selection()
  let (run, ledger) = whole_response_growth_start(
    selected, 16777216L, 33554432L,
  )
  let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  let retired = Ref(false)
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => retired.val).unwrap()
  let initial = @resources.ledger_usage(ledger)
  assert_true(@row_host.retire_row_run_response_workspace(borrow) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), initial)
  let body = @utf8.encode("[{\"id\":2},{\"id\":1}]")
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  @row_host.accept_charged_row_run_page(run, charge, body).unwrap() |> ignore
  @row_host.finish_row_run(run).unwrap()
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  let original = @row_host.row_capture_original_read(capture).unwrap()
  let captured = @resources.ledger_usage(ledger)
  assert_true(@row_host.retire_row_run_response_workspace(borrow) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), captured)
  retired.val = true
  @row_host.retire_row_run_response_workspace(borrow).unwrap()
  let remaining = @resources.ledger_usage(ledger)
  // The original retired provider declared R7/E9; page scratch was E20000.
  // Keep the independently retained input, holdings, receiver R/E and history.
  assert_eq(remaining, {
    ..captured,
    reserved_retention_bytes: captured.reserved_retention_bytes - 7L,
    reserved_execution_bytes: captured.reserved_execution_bytes - 20009L,
  })
  @row_host.retire_row_run_response_workspace(borrow).unwrap()
  assert_eq(@resources.ledger_usage(ledger), remaining)
  assert_true(@query.captured_source_available(source))
  assert_eq(@execution.supplied_relation_read_row_count(original), 2)
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, 0)
    is Some(@values.Number(2.0)),
  )
  // Returning construction workspace did not replace the original physical
  // cleanup observation or settle the still-live Source/input allocation.
  retired.val = false
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    remaining.reserved_execution_bytes,
  )
  retired.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.transferred_bytes, body.length().to_int64())
}

///|
test "WholeInput workspace return fences original observer reentry and cancellation" {
  let (_, _, selected) = whole_row_selection()
  for cancel in [false, true] {
    let (run, ledger) = whole_response_growth_start(
      selected, 16777216L, 33554432L,
    )
    let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
    let armed = Ref(false)
    let nested_refused = Ref(false)
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => {
      if armed.val {
        armed.val = false
        nested_refused.val = @row_host.retire_row_run_response_workspace(borrow)
          is Err(InvalidState)
        if cancel {
          @row_host.abort_row_run(run)
        }
      }
      true
    }).unwrap()
    let body = @utf8.encode("[{\"id\":1}]")
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    @row_host.accept_charged_row_run_page(run, charge, body).unwrap() |> ignore
    @row_host.finish_row_run(run).unwrap()
    assert_true(whole_row_validate(run))
    @row_host.capture_row_run(run).unwrap() |> ignore
    let before = @resources.ledger_usage(ledger)
    armed.val = true
    let result = @row_host.retire_row_run_response_workspace(borrow)
    assert_true(nested_refused.val)
    if cancel {
      assert_true(result is Err(_))
      assert_eq(@resources.ledger_usage(ledger), before)
    } else {
      result.unwrap()
      assert_eq(@resources.ledger_usage(ledger), {
        ..before,
        reserved_retention_bytes: before.reserved_retention_bytes - 7L,
        reserved_execution_bytes: before.reserved_execution_bytes - 20009L,
      })
    }
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      body.length().to_int64(),
    )
  }
}
