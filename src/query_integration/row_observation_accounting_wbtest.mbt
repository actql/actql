///|
test "ancillary identity response charges the original RowRun without fabricating a captured row" {
  let identity = @utf8.encode("{\"portalId\":7}")
  let body = row_page_body(2)
  let total = (identity.length() + body.length()).to_int64()
  let (run, ledger, plan) = row_page_run(
    "row-observation-success",
    transfer_bytes=total,
  )
  let identity_charge = @row_host.charge_row_run_page(run, identity).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    identity.length().to_int64(),
  )
  @row_host.consume_row_run_observation_charge(run, identity_charge).unwrap()
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_values(
      run,
      charge,
      ["id"],
      row_page_values(body, plan),
    ).unwrap(),
    1,
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, total)
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  let mut completed = false
  for _ in 0..<10000 {
    let (done, _) = @row_host.advance_row_capture(run, 1).unwrap()
    if done {
      completed = true
      break
    }
  }
  assert_true(completed)
  let capture = @row_host.capture_row_run(run).unwrap()
  let original = @row_host.row_capture_original_read(capture).unwrap()
  assert_eq(@execution.supplied_relation_read_row_count(original), 1)
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, 0)
    is Some(@admitted.Number(2)),
  )
  assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
  @row_host.close_row_run(run)
  let mut cleaned = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  @row_host.close_accounted_row_run(run).unwrap()
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, total)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_transfer_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_false(@execution.supplied_relation_read_available(original))
}

///|
test "foreign observation charge preserves its original owner and cannot fund another RowRun" {
  let (owner, owner_ledger, _) = row_page_run("row-observation-owner")
  let (foreign, foreign_ledger, _) = row_page_run("row-observation-foreign")
  let body = @utf8.encode("{\"portalId\":7}")
  let charge = @row_host.charge_row_run_page(owner, body).unwrap()
  assert_true(
    @row_host.consume_row_run_observation_charge(foreign, charge)
    is Err(Physical(ForeignOwner)),
  )
  assert_eq(@resources.ledger_usage(foreign_ledger).transferred_bytes, 0L)
  row_page_assert_closed(foreign, foreign_ledger)
  @row_host.consume_row_run_observation_charge(owner, charge).unwrap()
  assert_eq(
    @resources.ledger_usage(owner_ledger).transferred_bytes,
    body.length().to_int64(),
  )
  @row_host.close_accounted_row_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner_ledger).held_bytes, 0L)
}

///|
test "observation charge replay or an omitted ticket cannot complete the original read" {
  let body = @utf8.encode("{\"portalId\":7}")
  let (run, ledger, _) = row_page_run("row-observation-replay")
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  @row_host.consume_row_run_observation_charge(run, charge).unwrap()
  assert_true(
    @row_host.consume_row_run_observation_charge(run, charge)
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(run, ledger)
  let (omitted, omitted_ledger, _) = row_page_run("row-observation-omitted")
  @row_host.charge_row_run_page(omitted, body).unwrap() |> ignore
  assert_true(@row_host.finish_row_run(omitted) is Err(Physical(InvalidCharge)))
  row_page_assert_closed(omitted, omitted_ledger)
}

///|
test "observation response cannot extend the original transfer or per-response bound" {
  let body = @utf8.encode("{\"portalId\":7}")
  let (run, ledger, _) = row_page_run(
    "row-observation-transfer",
    transfer_bytes=body.length().to_int64() - 1L,
  )
  assert_true(
    @row_host.charge_row_run_page(run, body) is Err(Physical(TransferLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  row_page_assert_closed(run, ledger)
  let (small, small_ledger, _) = row_page_run(
    "row-observation-body",
    max_page_bytes=body.length() - 1,
  )
  assert_true(
    @row_host.charge_row_run_page(small, body) is Err(Source(InvalidPage)),
  )
  assert_eq(
    @resources.ledger_usage(small_ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(small, small_ledger)
}

///|
test "observation charge consumption requires the original accounted RowRun" {
  let (_, acquisition) = row_page_acquisition()
  let run = @row_host.start_row_acquisition(
    acquisition,
    "row-observation-unaccounted",
    _ => true,
  ).unwrap()
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let charge = @row_host.charge_row_run_page(
    run,
    @utf8.encode("{\"portalId\":7}"),
  ).unwrap()
  assert_true(
    @row_host.consume_row_run_observation_charge(run, charge)
    is Err(InvalidState),
  )
  // Refusal does not consume the ticket or manufacture transport completion.
  assert_true(@row_host.finish_row_run(run) is Err(Physical(InvalidCharge)))
  @row_host.close_row_run(run)
}
