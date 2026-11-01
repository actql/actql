///|
fn provider_workspace_capture(
  nonce : String,
  observe : () -> Bool,
) -> (
  @row_host.RowAcquisition,
  @resources.Ledger,
  @row_host.RowRun,
  @row_host.RowRunResponseBorrow,
  @row_host.RowSourceCapture,
) raise {
  let (declaration, acquisition) = row_page_acquisition()
  let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration,
    acquisition,
    row_page_observation(),
    100,
  ).unwrap()
  let ledger = provider_capacity_ledger(acquisition)
  let run = provider_capacity_start(acquisition, ledger, nonce)
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(borrow, observe).unwrap()
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
  (acquisition, ledger, run, borrow, capture)
}

///|
test "provider workspace retirement keeps live Source and all nonworkspace obligations until original cleanup" {
  let stopped = Ref(false)
  let observations = Ref(0)
  let (acquisition, ledger, run, borrow, capture) = provider_workspace_capture(
    "workspace-original",
    () => {
      observations.val += 1
      stopped.val
    },
  )
  let source = @row_host.row_capture_source(capture).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_host.retire_row_run_response_workspace(borrow)
    is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  stopped.val = true
  @row_host.retire_row_run_response_workspace(borrow).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after, {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - 2L,
  })
  assert_eq(
    after.reserved_execution_bytes,
    @row_host.row_acquisition_execution_capacity(acquisition) + 128L + 7L,
  )
  assert_true(
    physical_equal(@row_host.row_capture_source(capture).unwrap(), source),
  )
  let calls = observations.val
  @row_host.retire_row_run_response_workspace(borrow).unwrap()
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_eq(observations.val, calls)
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(observations.val, calls + 1)
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.attempts, before.attempts)
  assert_eq(closed.transferred_bytes, before.transferred_bytes)
  assert_true(@row_host.row_capture_source(capture) is Err(_))
  assert_true(
    @row_host.retire_row_run_response_workspace(borrow) is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), closed)
}

///|
test "provider workspace retirement fences same observer reentry without a second byte return" {
  let original : Ref[@row_host.RowRunResponseBorrow?] = Ref(None)
  let nested = Ref(0)
  let armed = Ref(true)
  let (_, ledger, run, borrow, capture) = provider_workspace_capture(
    "workspace-reentry",
    () => {
      if armed.val {
        armed.val = false
        if @row_host.retire_row_run_response_workspace(original.val.unwrap())
          is Err(InvalidState) {
          nested.val += 1
        }
      }
      true
    },
  )
  original.val = Some(borrow)
  let before = @resources.ledger_usage(ledger)
  @row_host.retire_row_run_response_workspace(borrow).unwrap()
  assert_eq(nested.val, 1)
  assert_eq(@resources.ledger_usage(ledger), {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - 2L,
  })
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "provider workspace retirement refuses observer closure without clearing cleanup authority or credit" {
  let original : Ref[@row_host.RowRun?] = Ref(None)
  let armed = Ref(true)
  let (_, ledger, run, borrow, capture) = provider_workspace_capture(
    "workspace-observer-close",
    () => {
      if armed.val {
        armed.val = false
        @row_host.close_row_run(original.val.unwrap())
      }
      true
    },
  )
  original.val = Some(run)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_host.retire_row_run_response_workspace(borrow)
    is Err(Evidence(UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@row_host.row_capture_source(capture) is Err(_))
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}

///|
test "provider workspace retirement cannot precede capture or replace the original cleanup binding" {
  let (_, acquisition) = row_page_acquisition()
  let ledger = provider_capacity_ledger(acquisition)
  let run = provider_capacity_start(
    acquisition, ledger, "workspace-before-capture",
  )
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_host.retire_row_run_response_workspace(borrow) is Err(InvalidState),
  )
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true).unwrap()
  assert_true(
    @row_host.retire_row_run_response_workspace(borrow) is Err(InvalidState),
  )
  assert_true(
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true)
    is Err(InvalidState),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @row_host.close_accounted_row_run(run).unwrap()
}
