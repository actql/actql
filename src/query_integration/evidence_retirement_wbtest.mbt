///|
priv struct EvidenceRetirementFixture {
  registration : @planning.QueryEvidenceRegistration[
    @planning.QueryEvidenceContracts,
    @planning.QueryRequirement,
    Ref[Int],
  ]
  authority : @planning.QueryEvidenceAttemptAuthority[
    @planning.QueryEvidenceContracts,
    @planning.QueryRequirement,
    Ref[Int],
  ]
  issuer : Ref[Int]
  attempt : Ref[Int]
  retention : @planning.MeasuredQueryRows
  issued : @planning.QueryEvidenceIssued[
    Ref[Int],
    Ref[Int],
    @planning.MeasuredQueryRows,
  ]
}

///|
fn evidence_retirement_fixture() -> EvidenceRetirementFixture raise {
  let f = broad_issuer_fixture()
  let (query, evidence) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query,
    evidence,
    query_capture_limits(),
  ).unwrap()
  let issuer = Ref(0)
  let attempt = Ref(0)
  // Test-only trusted Host: settlement is tied to this original attempt,
  // while rows, output, selection and evidence all use the real common APIs.
  let registration = @planning.register_query_evidence_issuer(
    contracts,
    f.requirement,
    "evidence-retirement",
    100,
    "test-host",
    candidate => physical_equal(candidate, attempt),
  ).unwrap()
  let (_, authority) = @planning.reserve_selected_query_evidence_attempt(
    registration,
    f.choice,
    f.prepared,
    _ => f.requirement,
  ).unwrap()
  let receipt = @query.admit_query_receipt(
    f.sequence,
    [
      input_cursor("{\"id\":3}"),
      input_cursor("{\"id\":1}"),
      input_cursor("{\"id\":2}"),
    ],
    3,
    run_limits().input_values,
  ).unwrap()
  let (completed, _) = @query.execute_query_receipt_guarded(
    f.sequence,
    receipt,
    compute_test_limits(),
    max_output_rows=2,
    max_value_bytes=100,
    query_guard_physical(),
  ).unwrap()
  let query = @query.query_sequence_requirement(f.sequence)
  let output = @execution.completed_output(
    completed,
    @acquisition.query_acquisition_capture(query),
  ).unwrap()
  let scan = @query.query_receipt_rows(receipt)
  let retention = @planning.measure_query_retention(scan, output, true, {
    received_wire_bytes: 28,
    retained_wire_bytes: 47,
    measurement: row_wire_limits(),
  }).unwrap()
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(@query.query_sequence_owner(f.sequence)),
    @acquisition.query_acquisition_input(query),
  ).unwrap()
  let issued = @planning.issue_query_evidence(
    registration,
    authority,
    issuer,
    attempt,
    retention,
    retention,
    scan,
    output,
    schema,
    query_material_limits(),
  ).unwrap()
  @duckdb_query.close_duckdb_query_issuer(f.issuer)
  { registration, authority, issuer, attempt, retention, issued, }
}

///|
fn evidence_retirement_records(
  f : EvidenceRetirementFixture,
) -> Array[(String, String)] {
  Array::makei(3, i => {
    let (document, cid) = @planning.query_evidence_record_at(f.issued, i).unwrap()
    (@encode.document_text(document), cid)
  })
}

///|
test "common issued retirement revokes only its original custody and preserves record DATA" {
  let f = evidence_retirement_fixture()
  let foreign = evidence_retirement_fixture()
  let before = evidence_retirement_records(f)
  assert_true(@planning.retire_query_evidence_custody(f.issued))
  assert_true(@planning.retire_query_evidence_custody(f.issued))
  assert_true(@planning.query_evidence_registration_live(f.registration))
  assert_true(
    @planning.verify_query_evidence_issued(
      f.issued,
      f.registration,
      f.authority,
      f.issuer,
      f.attempt,
      f.retention,
    )
    is Err(ForeignRecords),
  )
  assert_true(
    @planning.capture_query_evidence(
      f.issued,
      f.registration,
      f.authority,
      f.issuer,
      f.attempt,
      f.retention,
      query_capture_limits(),
    )
    is Err(ForeignRecords),
  )
  assert_eq(evidence_retirement_records(f), before)
  assert_true(
    @planning.verify_query_evidence_issued(
      foreign.issued,
      foreign.registration,
      foreign.authority,
      foreign.issuer,
      foreign.attempt,
      foreign.retention,
    )
    is Ok(_),
  )
  assert_true(@planning.retire_query_evidence_custody(foreign.issued))
  @planning.close_query_evidence_registration(f.registration)
  @planning.close_query_evidence_registration(foreign.registration)
}

///|
test "common captured retirement requires its closed registration and retains immutable DATA aliases" {
  let f = evidence_retirement_fixture()
  let captured = @planning.capture_query_evidence(
    f.issued,
    f.registration,
    f.authority,
    f.issuer,
    f.attempt,
    f.retention,
    query_capture_limits(),
  ).unwrap()
  let records = evidence_retirement_records(f)
  let document = @planning.query_evidence_capture_document(captured)
  let text = @encode.document_text(document)
  let cid = @planning.query_evidence_capture_cid(captured)
  let usage = @planning.query_evidence_capture_usage(captured)
  assert_false(@planning.retire_query_evidence_custody(f.issued))
  assert_true(
    @planning.verify_query_evidence_captured(
      captured,
      f.registration,
      f.authority,
      f.issuer,
      f.attempt,
      f.retention,
    )
    is Ok(_),
  )
  @planning.close_query_evidence_registration(f.registration)
  assert_true(@planning.retire_query_evidence_custody(f.issued))
  assert_true(@planning.retire_query_evidence_custody(f.issued))
  assert_true(
    @planning.verify_query_evidence_captured(
      captured,
      f.registration,
      f.authority,
      f.issuer,
      f.attempt,
      f.retention,
    )
    is Err(IssuerClosed),
  )
  assert_true(
    physical_equal(
      @planning.query_evidence_capture_document(captured),
      document,
    ),
  )
  assert_eq(@encode.document_text(document), text)
  assert_eq(@planning.query_evidence_capture_cid(captured), cid)
  assert_eq(@planning.query_evidence_capture_usage(captured), usage)
  assert_eq(evidence_retirement_records(f), records)
}

///|
test "broad capture abort is nondestructive while closed cleanup retires custody and keeps DATA" {
  let f = broad_issuer_fixture()
  let attempt = broad_issued_attempt(f)
  broad_issued_run(f, attempt)
  let records = @duckdb_query.issue_duckdb_broad_records(
    attempt,
    query_material_limits(),
  ).unwrap()
  let observation = @duckdb_query.capture_duckdb_broad_query(
    f.issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let document = @duckdb_query.duckdb_broad_observation_document(observation)
  let text = @encode.document_text(document)
  let cid = @duckdb_query.duckdb_broad_observation_cid(observation)
  let before = Array::makei(3, i => {
    let (document, cid) = @duckdb_query.duckdb_broad_record_at(records, i).unwrap()
    (@encode.document_text(document), cid)
  })
  @duckdb_query.abort_duckdb_broad_attempt(attempt)
  assert_eq(@duckdb_query.duckdb_broad_attempt_row_count(attempt), Some(2))
  assert_true(
    @duckdb_query.verify_duckdb_broad_records(f.issuer, attempt, records)
    is Ok(_),
  )
  assert_false(@duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap())
  let source = @duckdb_query.broad_captured_source(
    f.issuer,
    attempt,
    observation,
  ).unwrap()
  assert_true(@query.captured_source_available(source))
  @duckdb_query.close_duckdb_query_issuer(f.issuer)
  assert_true(@duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap())
  assert_true(@duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap())
  assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
  assert_false(@query.captured_source_available(source))
  assert_true(
    @duckdb_query.verify_duckdb_broad_records(f.issuer, attempt, records)
    is Err(IssuerClosed),
  )
  assert_true(
    physical_equal(
      @duckdb_query.duckdb_broad_observation_document(observation),
      document,
    ),
  )
  assert_eq(@encode.document_text(document), text)
  assert_eq(@duckdb_query.duckdb_broad_observation_cid(observation), cid)
  for i in 0..<3 {
    let (document, cid) = @duckdb_query.duckdb_broad_record_at(records, i).unwrap()
    assert_eq((@encode.document_text(document), cid), before[i])
  }
  f.transport.clear()
}

///|
test "failed broad capture retires issued custody without erasing diagnostic records" {
  let f = broad_issuer_fixture()
  for capture_failure in [false, true] {
    let attempt = broad_issued_attempt(f)
    broad_issued_run(f, attempt)
    let records = @duckdb_query.issue_duckdb_broad_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let (document, cid) = @duckdb_query.duckdb_broad_record_at(records, 0).unwrap()
    let text = @encode.document_text(document)
    if capture_failure {
      assert_true(
        @duckdb_query.capture_duckdb_broad_query(f.issuer, attempt, records, {
          ..query_capture_limits(),
          max_bytes: 0,
        })
        is Err(Encoding(_)),
      )
    } else {
      @duckdb_query.abort_duckdb_broad_attempt(attempt)
    }
    assert_true(@duckdb_query.duckdb_broad_attempt_row_count(attempt) is None)
    assert_true(@duckdb_query.cleanup_duckdb_broad_residual(attempt).unwrap())
    assert_true(
      @duckdb_query.verify_duckdb_broad_records(f.issuer, attempt, records)
      is Err(ForeignRecords),
    )
    let (after, after_cid) = @duckdb_query.duckdb_broad_record_at(records, 0).unwrap()
    assert_true(physical_equal(after, document))
    assert_eq((@encode.document_text(after), after_cid), (text, cid))
  }
  @duckdb_query.close_duckdb_query_issuer(f.issuer)
  f.transport.clear()
}

///|
test "accounted Row capture survives abort and retains failed cleanup until original confirmation" {
  let stopped = Ref(false)
  let (_, ledger, run, _, capture) = provider_workspace_capture(
    "row-evidence-retirement",
    () => stopped.val,
  )
  let source = @row_host.row_capture_source(capture).unwrap()
  @row_host.abort_row_run(run)
  assert_true(@query.captured_source_available(source))
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @row_host.close_accounted_row_run(run) is Err(Evidence(UnverifiedTransport)),
  )
  let pending = @resources.ledger_usage(ledger)
  assert_eq(pending.held_bytes, before.held_bytes)
  assert_eq(pending.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_false(@query.captured_source_available(source))
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger), closed)
  assert_true(@row_host.row_capture_source(capture) is Err(Unavailable))
}

///|
test "unaccounted Row captures retire after synchronous close or actual residual cleanup" {
  for bounded in [false, true] {
    let (declaration, acquisition) = row_page_acquisition()
    let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
      declaration,
      acquisition,
      row_page_observation(),
      100,
    ).unwrap()
    let run = @row_host.start_row_acquisition(
      acquisition,
      "unaccounted-evidence-retirement",
      _ => true,
    ).unwrap()
    @row_host.begin_row_run(run, 128, 10, 10).unwrap()
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
    if bounded {
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
    }
    let capture = @row_host.capture_row_run(run).unwrap()
    let source = @row_host.row_capture_source(capture).unwrap()
    assert_true(@query.captured_source_available(source))
    @row_host.close_row_run(run)
    assert_false(@query.captured_source_available(source))
    let mut cleaned = false
    for _ in 0..<10000 {
      if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
        cleaned = true
        break
      }
    }
    assert_true(cleaned)
    assert_true(@row_host.cleanup_row_capture(run).unwrap())
    @row_host.close_row_run(run)
    assert_true(@row_host.cleanup_row_capture(run).unwrap())
    assert_true(@row_host.row_capture_source(capture) is Err(Unavailable))
  }
}
