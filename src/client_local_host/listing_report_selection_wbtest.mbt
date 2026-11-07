///|
// Checked Catalog/Query and actual existing Row capture state. Physical read,
// reference issuance and declaration sizes remain deterministic fixtures; this
// is not installed Source authorization or a normal report-capacity supplier.
priv struct ListingReportSelectionFixture {
  prepared : @publication_host.PreparedClientProgram
  acquisition : @row_source_host.RowAcquisition
  requirement : @planning.QueryRequirement
  run : @row_source_host.RowRun
  capture : @row_source_host.RowSourceCapture
  ledger : @resources.Ledger
}

///|
fn listing_report_selection_fixture(
  accounted : Bool,
  reports_selected : Bool,
) -> ListingReportSelectionFixture raise {
  let (declaration, prepared, _, _, _, _, requirement) = original_keyed_run_fixture(
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
  let acquisition = @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-explicit-listing-selection", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  let body = @utf8.encode(
    "{\"items\":[],\"request_token\":null,\"next_token\":null}",
  )
  let retained = @row_source_host.row_acquisition_retained_capacity(acquisition)
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: body.length().to_int64(),
    retained_bytes: retained + (if reports_selected { 7L + 40L } else { 0L }),
    execution_bytes: execution +
    4096L +
    (if reports_selected { 9L + 40L } else { 0L }),
  }).unwrap()
  let run = if reports_selected {
    assert_true(accounted)
    @row_source_host.start_accounted_listing_row_acquisition(
      acquisition,
      @execution.execution_capacity(7L, 9L),
      "explicit-report-profile",
      _ => true,
      ledger,
      body.length().to_int64(),
      4096L,
    ).unwrap()
  } else if accounted {
    @row_source_host.start_accounted_row_acquisition(
      acquisition,
      "ordinary-resolved-listing",
      _ => true,
      ledger,
      body.length().to_int64(),
      4096L,
    ).unwrap()
  } else {
    @row_source_host.start_row_acquisition(
      acquisition,
      "ordinary-unaccounted-listing",
      _ => true,
    ).unwrap()
  }
  let issuer = @admitted.bind_reference_issuer(
    (_, _) => abort("empty listing must not issue references"),
    _ => abort("empty listing must not observe references"),
  )
  @row_source_host.begin_row_run(run, 4096, 3, 3, reference_issuer=Some(issuer)).unwrap()
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
  { prepared, acquisition, requirement, run, capture, ledger, }
}

///|
fn listing_selection_evidence(
  fixture : ListingReportSelectionFixture,
  reports_required : Bool,
) -> Result[@publication.RunEvidenceValue, @row_source_host.RowHostIssue] {
  let source = @row_source_host.row_capture_source(fixture.capture).unwrap()
  let limits = original_keyed_content_workspace().export_limits
  let identity = @query.identify_captured_source_relation(
    source,
    3,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let logical = @publication_host.issue_captured_source_input_logical(
    @publication_host.prepared_client_graph(fixture.prepared),
    source,
    identity,
    fixture.requirement,
  ).unwrap()
  let facts = @planning.query_requirement_source_evidence_facts(
    fixture.requirement,
  ).unwrap()
  let policy = @planning.query_source_evidence_fact_values(facts)[3]
  let authority = "sha256:" + "2".repeat(64)
  if reports_required {
    @row_source_host.issue_row_listing_source_evidence(
      fixture.acquisition,
      fixture.capture,
      identity,
      logical,
      authority,
      policy,
      "2026-10-14T00:00:01.000Z",
    )
  } else {
    @row_source_host.issue_row_source_evidence(
      fixture.acquisition,
      fixture.capture,
      identity,
      logical,
      authority,
      policy,
      "2026-10-14T00:00:01.000Z",
    )
  }
}

///|
test "ordinary accounted listing retains its original settlement and evidence scope without report adoption" {
  let fixture = listing_report_selection_fixture(true, false)
  let captured = @resources.ledger_usage(fixture.ledger)
  assert_eq(captured.attempts, 1)
  assert_eq(captured.held_bytes, 22404100L)
  assert_eq(captured.reserved_retention_bytes, 0L)
  assert_eq(captured.reserved_execution_bytes, 0L)
  let ordinary = listing_selection_evidence(fixture, false).unwrap()
  assert_false(
    @publication.run_evidence_value_json(ordinary).contains(
      "\"file_listing_reports\"",
    ),
  )
  assert_true(
    listing_selection_evidence(fixture, true)
    is Err(
      @row_source_host.SourceEvidence(@row_source_host.ObservationUnavailable)
    ),
  )
  assert_eq(@resources.ledger_usage(fixture.ledger), captured)
  @row_source_host.close_accounted_row_run(fixture.run).unwrap()
  assert_eq(@resources.ledger_usage(fixture.ledger).held_bytes, 0L)
}

///|
test "ordinary unaccounted listing evidence cannot be promoted to an empty report profile" {
  let fixture = listing_report_selection_fixture(false, false)
  let before = @resources.ledger_usage(fixture.ledger)
  assert_eq(before.attempts, 0)
  let ordinary = listing_selection_evidence(fixture, false).unwrap()
  assert_false(
    @publication.run_evidence_value_json(ordinary).contains(
      "\"file_listing_reports\"",
    ),
  )
  assert_true(
    listing_selection_evidence(fixture, true)
    is Err(
      @row_source_host.SourceEvidence(@row_source_host.ObservationUnavailable)
    ),
  )
  assert_eq(@resources.ledger_usage(fixture.ledger), before)
  @row_source_host.close_row_run(fixture.run)
  assert_true(@row_source_host.row_capture_source(fixture.capture) is Err(_))
}

///|
test "explicit report listing keeps its extra reservation and issues actual empty correlation only while live" {
  let fixture = listing_report_selection_fixture(true, true)
  let captured = @resources.ledger_usage(fixture.ledger)
  assert_eq(captured.attempts, 1)
  assert_eq(captured.held_bytes, 22404100L)
  assert_true(captured.reserved_retention_bytes > 0L)
  assert_true(captured.reserved_execution_bytes > 0L)
  let report = listing_selection_evidence(fixture, true).unwrap()
  assert_true(
    @publication.run_evidence_value_json(report).contains(
      "\"file_listing_reports\":{\"row_count\":0,\"rows\":[]}",
    ),
  )
  assert_eq(@resources.ledger_usage(fixture.ledger), captured)
  @row_source_host.close_accounted_row_run(fixture.run).unwrap()
  assert_true(@row_source_host.row_capture_source(fixture.capture) is Err(_))
  let retired = @resources.ledger_usage(fixture.ledger)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
}
