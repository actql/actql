///|
// Real checked Catalog/Query and the existing Row Source owner. Transport and
// reference issuance remain deterministic fixtures, not public authorization
// or an adopted installed Node physical profile.
fn listing_report_acquisition_fixture() -> @row_source_host.RowAcquisition raise {
  let (declaration, _, _, _, _, _, requirement) = original_keyed_run_fixture(
    selector_free=true,
  )
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @row_source_host.row_declaration_view(
    declaration,
    facts.source_ref,
  ).unwrap()
  let source = @row_source_host.prepare_declared_row_source(
    requirement, "content-fixture", view,
  ).unwrap()
  @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-listing-report-capacity", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
}

///|
test "checked listing refuses missing capacity and either shortage before the original attempt or input" {
  let acquisition = listing_report_acquisition_fixture()
  assert_true(@row_source_host.row_acquisition_is_listing(acquisition))
  assert_eq(
    @row_source_host.row_acquisition_listing_report_bounds(acquisition).unwrap(),
    (3L, 9L),
  )
  let retained = @row_source_host.row_acquisition_retained_capacity(acquisition)
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  // Original configuration binding adds H1/R2/W1 = 40 tariff bytes.
  // Small independent accounting units exercise addition/reservation only.
  // They are intentionally NOT supplied through a production installation.
  let declaration = @execution.execution_capacity(7L, 9L).unwrap()
  for shortage in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 0L,
      retained_bytes: retained +
      7L +
      40L -
      (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: execution +
      9L +
      40L -
      (if shortage == 2 { 1L } else { 0L }),
    }).unwrap()
    let before = @resources.ledger_usage(ledger)
    let confirmations = Ref(0)
    let verify = (_ : @row_source_host.RowAttempt) => {
      confirmations.val += 1
      true
    }
    assert_true(
      @row_source_host.start_accounted_listing_row_acquisition(
        acquisition,
        None,
        "missing-listing-capacity",
        verify,
        ledger,
        0L,
        0L,
      )
      is Err(@row_source_host.Physical(@resources.InvalidLimits)),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    let started = @row_source_host.start_accounted_listing_row_acquisition(
      acquisition,
      Some(declaration),
      "selected-listing-capacity",
      verify,
      ledger,
      0L,
      0L,
    )
    if shortage == 0 {
      let run = started.unwrap()
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        retained + 7L + 40L,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        execution + 9L + 40L,
      )
      @row_source_host.close_accounted_row_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    } else {
      assert_true(
        if shortage == 1 {
          started is Err(@row_source_host.Physical(@resources.RetentionLimit))
        } else {
          started is Err(@row_source_host.Physical(@resources.ExecutionLimit))
        },
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
    assert_eq(confirmations.val, 0)
  }
}

///|
test "actual empty listing capture keeps encoding allowance until the same Row child cleanup" {
  let acquisition = listing_report_acquisition_fixture()
  let retained = @row_source_host.row_acquisition_retained_capacity(acquisition)
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  let body = @utf8.encode(
    "{\"items\":[],\"request_token\":null,\"next_token\":null}",
  )
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: body.length().to_int64(),
    retained_bytes: retained + 7L + 40L,
    execution_bytes: execution + 9L + 40L + 4096L,
  }).unwrap()
  let run = @row_source_host.start_accounted_listing_row_acquisition(
    acquisition,
    @execution.execution_capacity(7L, 9L),
    "empty-listing-postcapture",
    _ => true,
    ledger,
    body.length().to_int64(),
    4096L,
  ).unwrap()
  let references = Ref(0)
  let issuer = @admitted.bind_reference_issuer(
    (_, _) => {
      references.val += 1
      false
    },
    _ => false,
  )
  @row_source_host.begin_row_run(run, 4096, 3, 3, reference_issuer=Some(issuer)).unwrap()
  let foreign = listing_report_acquisition_fixture()
  assert_true(
    @row_source_host.borrow_row_run_responses(run, foreign)
    is Err(@row_source_host.ForeignDeclaration),
  )
  let original_borrow = @row_source_host.borrow_row_run_responses(
    run, acquisition,
  ).unwrap()
  @row_source_host.check_row_run_response_borrow_current(original_borrow).unwrap()
  @row_source_host.begin_row_run_listing_request(run, None, 0L).unwrap()
  @row_source_host.begin_row_run_listing_page(run, body, 0L).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    match @row_source_host.advance_row_run_listing_page(run, 1, 0L).unwrap() {
      @row_source_host.ListingPageContinue(_) => ()
      @row_source_host.ListingPageComplete(rows~, ..) => {
        assert_eq(rows, 0)
        complete = true
        break
      }
    }
  }
  assert_true(complete)
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  assert_eq(
    @query.captured_source_row_count(
      @row_source_host.row_capture_source(capture).unwrap(),
    ),
    Some(0),
  )
  let postcapture = @resources.ledger_usage(ledger)
  // Original 22404096 + two independently authored canonical [] wires.
  assert_eq(postcapture.held_bytes, 22404100L)
  assert_eq(
    postcapture.reserved_retention_bytes,
    retained + 7L + 40L - 22404100L,
  )
  assert_eq(postcapture.reserved_execution_bytes, execution + 9L + 40L + 4096L)
  assert_eq(references.val, 0)
  // The next asynchronous evidence phase still owns its original allowance.
  assert_true(
    @resources.reserve_capacity(ledger, 0L, 1L)
    is Err(@resources.ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), postcapture)
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_true(@row_source_host.row_capture_source(capture) is Err(_))
  assert_true(
    @row_source_host.check_row_run_response_borrow_current(original_borrow)
    is Err(@row_source_host.InvalidState),
  )
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_eq(retired.attempts, 1)
}

///|
test "listing supplier cannot change an ordinary checked Source into a listing attempt" {
  let (prepared, _, _, _) = original_prefix_execution_fixture(source=true)
  let ordinary = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  assert_false(@row_source_host.row_acquisition_is_listing(ordinary))
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(ordinary) +
    7L,
    execution_bytes: @row_source_host.row_acquisition_execution_capacity(
      ordinary,
    ) +
    9L,
  }).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_source_host.start_accounted_listing_row_acquisition(
      ordinary,
      @execution.execution_capacity(7L, 9L),
      "foreign-listing-supplier",
      _ => abort("foreign Source must not reach transport"),
      ledger,
      0L,
      0L,
    )
    is Err(@row_source_host.Source(@row_source_host.ForeignSource)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
}
