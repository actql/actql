///|
fn whole_actual_input_limits() -> @row_host.RowInputLimits {
  {
    max_rows: 1000000,
    page: { max_bytes: 20000, max_nodes: 10000, max_depth: 20, max_rows: 128, },
    retention: {
      max_nodes: 1000000,
      max_text_bytes: 8000000,
      max_depth: 1000,
      max_work: 100000000,
    },
    wire: {
      max_columns: 1,
      max_order_work: 10000,
      max_bytes: 8000000,
      max_nodes: 1000000,
      max_depth: 1000,
    },
  }
}

///|
fn whole_actual_start(
  selected : @row_host.RowInputAcquisition,
  retained : Int64,
  execution : Int64,
) -> (@row_host.RowRun, @resources.Ledger, Ref[Bool]) {
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 20000L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    None,
    "actual-whole",
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
  let stopped = Ref(false)
  let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  (run, ledger, stopped)
}

///|
test "whole actual capacity accepts larger semantic ceilings without reserving future maxima" {
  let (_, _, small) = whole_row_selection()
  let (_, _, large) = whole_row_selection(
    input_limits=Some(whole_actual_input_limits()),
  )
  let initial = @row_host.row_input_acquisition_capacity(large, None).unwrap()
  let small_capacity = @row_host.row_input_acquisition_capacity(small, None).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_retained_bytes(small_capacity),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(initial),
    @execution.execution_capacity_execution_bytes(small_capacity),
  )
  let r = @execution.execution_capacity_retained_bytes(initial)
  let e = @execution.execution_capacity_execution_bytes(initial) + 20000L
  // Independent material scale: fixed original controls, not 8MB of wire or
  // a million retained node slots merely because the policy permits them.
  assert_true(r < 65536L)
  assert_true(e < 131072L)
  for retained_short in [true, false] {
    let ledger = @resources.create_ledger({
      planning_work: 100,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 20000L,
      retained_bytes: if retained_short {
        r - 1L
      } else {
        r
      },
      execution_bytes: if retained_short {
        e
      } else {
        e - 1L
      },
    }).unwrap()
    assert_true(
      @row_host.start_accounted_row_input_acquisition(
        large,
        None,
        "initial-one-short",
        _ => true,
        ledger,
        20000L,
        20000L,
      )
      is Err(Physical(_)),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "whole actual page grows before decode and preserves physical pending on either refusal" {
  let (_, _, selected) = whole_row_selection(
    input_limits=Some(whole_actual_input_limits()),
  )
  let capacity = @row_host.row_input_acquisition_capacity(selected, None).unwrap()
  let r = @execution.execution_capacity_retained_bytes(capacity)
  let e = @execution.execution_capacity_execution_bytes(capacity) + 20000L
  let body = @utf8.encode("[{\"id\":2},{\"id\":1}]")
  for mode in 0..<3 {
    let (run, ledger, stopped) = whole_actual_start(
      selected,
      if mode == 0 {
        r
      } else {
        16777216L
      },
      if mode == 1 {
        e
      } else {
        33554432L
      },
    )
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    let accepted = @row_host.accept_charged_row_run_page(run, charge, body)
    if mode < 2 {
      assert_true(accepted is Err(Physical(_)))
      assert_true(@row_host.capture_row_run(run) is Err(_))
    } else {
      assert_eq(accepted.unwrap(), 2)
      let after_page = @resources.ledger_usage(ledger)
      assert_true(after_page.reserved_retention_bytes > r)
      assert_true(after_page.reserved_execution_bytes > e)
      @row_host.finish_row_run(run).unwrap()
      assert_true(whole_row_validate(run))
      assert_true(
        @resources.ledger_usage(ledger).reserved_execution_bytes >
        after_page.reserved_execution_bytes,
      )
      let capture = @row_host.capture_row_run(run).unwrap()
      assert_eq(
        @query.captured_source_row_count(
          @row_host.row_capture_source(capture).unwrap(),
        ),
        Some(2),
      )
    }
    assert_true(
      @row_host.accept_charged_row_run_page(run, charge, body) is Err(_),
    )
    assert_true(@row_host.close_accounted_row_run(run) is Err(_))
    assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
    stopped.val = true
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      body.length().to_int64(),
    )
  }
}

///|
test "whole actual validation refuses insufficient scratch after a fully admitted page" {
  let (_, _, selected) = whole_row_selection(
    input_limits=Some(whole_actual_input_limits()),
  )
  let body = @utf8.encode("[{\"id\":1}]")
  let (probe, ledger, stopped) = whole_actual_start(
    selected, 16777216L, 33554432L,
  )
  let charge = @row_host.charge_row_run_page(probe, body).unwrap()
  @row_host.accept_charged_row_run_page(probe, charge, body).unwrap() |> ignore
  let page = @resources.ledger_usage(ledger)
  stopped.val = true
  @row_host.close_accounted_row_run(probe).unwrap()
  let (run, tight, current_stop) = whole_actual_start(
    selected,
    page.reserved_retention_bytes,
    page.reserved_execution_bytes,
  )
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  @row_host.accept_charged_row_run_page(run, charge, body).unwrap() |> ignore
  @row_host.finish_row_run(run).unwrap()
  assert_true(@row_host.begin_row_capture(run) is Err(Physical(_)))
  assert_true(@row_host.capture_row_run(run) is Err(_))
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  current_stop.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(tight).reserved_execution_bytes, 0L)
}

///|
test "whole actual projected and checked provider pages fund receiver backing without a second parse" {
  let (prepared, _, selected) = whole_row_selection(
    input_limits=Some(whole_actual_input_limits()),
  )
  let body = @utf8.encode("[{\"id\":2},{\"id\":1}]")
  for typed in [false, true] {
    let (run, ledger, stopped) = whole_actual_start(
      selected, 16777216L, 33554432L,
    )
    let before = @resources.ledger_usage(ledger)
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    let accepted = if typed {
      let owner = @strategy.graph_task_owner(prepared.graph, 0).unwrap()
      let schema = @lower.preparation_input_schema(
        @lower.bound_preparation(owner),
        0,
      ).unwrap()
      let contract = @schema.field_at(schema, 0).unwrap().contract
      let rows = [
        [@values.checked_number_value(2.0, contract).unwrap()],
        [@values.checked_number_value(1.0, contract).unwrap()],
      ]
      @row_host.accept_charged_row_run_values(run, charge, ["id"], rows)
    } else {
      let page = @row_host.project_row_source_typed_json_page(
        body,
        [],
        false,
        [],
        20000,
        10000,
        20,
        128,
        0,
      ).unwrap()
      @row_host.accept_charged_row_run_projected_page(run, charge, page)
    }
    match accepted {
      Ok(count) => assert_eq(count, 2)
      Err(issue) =>
        fail(
          (if typed { "checked provider: " } else { "projected provider: " }) +
          (match issue {
            Source(value) => "Source " + @debug.to_string(value)
            Physical(value) => "Physical " + @debug.to_string(value)
            InvalidState => "InvalidState"
            _ => "other RowHostIssue"
          }),
        )
    }
    assert_true(
      @resources.ledger_usage(ledger).reserved_retention_bytes >
      before.reserved_retention_bytes,
    )
    @row_host.finish_row_run(run).unwrap()
    assert_true(whole_row_validate(run))
    let capture = @row_host.capture_row_run(run).unwrap()
    let read = @row_host.row_capture_original_read(capture).unwrap()
    assert_eq(@execution.supplied_relation_read_row_count(read), 2)
    assert_true(
      @execution.supplied_relation_read_cell(read, 0, 0)
      is Some(@values.Number(2.0)),
    )
    assert_true(@row_host.close_accounted_row_run(run) is Err(_))
    stopped.val = true
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "whole typed page shape refuses before payload inventory or growth" {
  let (_, _, selected) = whole_row_selection(
    input_limits=Some(whole_actual_input_limits()),
  )
  let initial = @row_host.row_input_acquisition_capacity(selected, None).unwrap()
  let r = @execution.execution_capacity_retained_bytes(initial)
  let e = @execution.execution_capacity_execution_bytes(initial) + 20000L
  let value = @values.checked_number_value(
    1.0,
    @contract.primitive(@contract.NumberType, nullable=false),
  ).unwrap()
  for mode in 0..<4 {
    let (run, ledger, stopped) = whole_actual_start(selected, r, e)
    let body = @utf8.encode("[]")
    let ticket = @row_host.charge_row_run_page(run, body).unwrap()
    let columns = if mode == 0 {
      ["foreign"]
    } else if mode == 3 {
      []
    } else {
      ["id"]
    }
    let rows = if mode == 1 {
      [Array::make(4096, value)]
    } else if mode == 2 {
      Array::make(129, [value])
    } else {
      [[value]]
    }
    assert_true(
      @row_host.accept_charged_row_run_values(run, ticket, columns, rows)
      is Err(Source(InvalidPage)),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, e)
    assert_true(@row_host.capture_row_run(run) is Err(_))
    assert_true(@row_host.close_accounted_row_run(run) is Err(_))
    stopped.val = true
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}
