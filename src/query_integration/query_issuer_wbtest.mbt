///|
fn query_issuer_fixture() -> (@mock.MockQueryIssuer, @query.QuerySequence) raise {
  let (program, sequence) = query_program_fixture()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    program,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "test-process", 100,
  ).unwrap()
  (issuer, sequence)
}

///|
fn query_issuer_attempt(
  issuer : @mock.MockQueryIssuer,
  sequence : @query.QuerySequence,
  route : @mock.QueryRealization,
  rows? : Array[String]? = None,
) -> @mock.MockQueryAttempt {
  let inputs = match rows {
    Some(rows) => rows.map(input_cursor)
    None =>
      [
        input_cursor("{\"id\":3}"),
        input_cursor("{\"id\":1}"),
        input_cursor("{\"id\":2}"),
      ]
  }
  @mock.prepare_issued_mock_query_attempt(
    issuer,
    strategy_for(sequence, route),
    inputs,
    inputs.length(),
  ).unwrap()
}

///|
fn query_issuer_run(
  attempt : @mock.MockQueryAttempt,
  retention? : @mock.MockRetentionLimits = query_retention_limits(),
) -> Unit {
  @mock.execute_mock_query(
    attempt,
    mock_strategy_limits(),
    guard_measure=Some(query_guard_physical()),
  ).unwrap()
  |> ignore
  @mock.retain_mock_query(attempt, retention).unwrap() |> ignore
}

///|
test "mock evidence requires prebound issuer and all guards and retention" {
  let (issuer, sequence) = query_issuer_fixture()
  let attempt = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
  assert_true(
    @mock.issue_mock_query_records(attempt, query_material_limits())
    is Err(NotRetained),
  )
  @mock.execute_mock_query(
    attempt,
    mock_strategy_limits(),
    guard_measure=Some(query_guard_physical()),
  ).unwrap()
  |> ignore
  assert_true(
    @mock.issue_mock_query_records(attempt, query_material_limits())
    is Err(NotRetained),
  )
  @mock.retain_mock_query(attempt, query_retention_limits()).unwrap() |> ignore
  let records = @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap()
  assert_true(
    @mock.verify_mock_query_records(issuer, attempt, records) is Ok(_),
  )
  assert_true(
    @mock.issue_mock_query_records(attempt, query_material_limits())
    is Err(NotRetained),
  )
  assert_true(@mock.mock_query_record_at(records, -1) is None)
  assert_true(@mock.mock_query_record_at(records, 3) is None)
  for (i, role) in [(0, "source_validation"), (1, "filter"), (2, "select")] {
    let (document, cid) = @mock.mock_query_record_at(records, i).unwrap()
    let text = @encode.document_text(document)
    assert_true(text.contains("\"role\":\"" + role + "\""))
    assert_true(text.contains("\"snapshot\":null"))
    assert_true(text.contains("\"received_bytes\":19"))
    assert_true(text.contains("\"received_rows\":2"))
    assert_true(text.contains("\"row_count\":2"))
    // Independent selected-scan scope: the empty resolved request and selected
    // SourceView contract, not the Catalog or only the received output.
    assert_true(
      text.contains(
        query_material_expected(
          (
            #|{"version":"actql-query-scan-scope/0.1","source_ref":"connector://crm/main/r#v","source_contract_cid":"sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f","resolved_request_cid":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
          ),
        ),
      ),
    )
    assert_true(
      text.contains(
        "sha256:b578d4eb7cd3e1c8e66fd5758a9c5a98dc05739e4c6fa282fc372aec70930e18",
      ),
    )
    assert_eq(query_material_expected(text), cid)
  }
  // A separately held computation or retention cannot add provenance afterward.
  let unissued = query_retention_attempt(@mock.NativeQuery)
  @mock.retain_mock_query(unissued, query_retention_limits()).unwrap() |> ignore
  assert_true(
    @mock.issue_mock_query_records(unissued, query_material_limits())
    is Err(UnauthorizedAttempt),
  )
}

///|
test "mock issued records keep attempt and actual access distinct" {
  let (issuer, sequence) = query_issuer_fixture()
  let native = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
  let broad = query_issuer_attempt(issuer, sequence, @mock.BroadWithResidual)
  query_issuer_run(native)
  query_issuer_run(broad)
  let first = @mock.issue_mock_query_records(native, query_material_limits()).unwrap()
  let second = @mock.issue_mock_query_records(broad, query_material_limits()).unwrap()
  assert_true(
    @mock.verify_mock_query_records(issuer, native, second)
    is Err(UnauthorizedAttempt),
  )
  assert_true(
    @mock.verify_mock_query_records(issuer, broad, first)
    is Err(UnauthorizedAttempt),
  )
  let (other, _) = query_issuer_fixture()
  assert_true(
    @mock.verify_mock_query_records(other, native, first)
    is Err(UnauthorizedAttempt),
  )
  let (first_doc, first_cid) = @mock.mock_query_record_at(first, 0).unwrap()
  let (second_doc, second_cid) = @mock.mock_query_record_at(second, 0).unwrap()
  assert_true(first_cid != second_cid)
  assert_true(@encode.document_text(first_doc).contains("\"attempt\":\"0\""))
  assert_true(@encode.document_text(second_doc).contains("\"attempt\":\"1\""))
  assert_true(
    @encode.document_text(second_doc).contains("\"received_bytes\":28"),
  )
  assert_true(@encode.document_text(second_doc).contains("\"received_rows\":3"))
  assert_true(@mock.cancel_mock_query(native))
  assert_true(
    @mock.verify_mock_query_records(issuer, native, first)
    is Err(ForeignRecords),
  )
  assert_true(@mock.verify_mock_query_records(issuer, broad, second) is Ok(_))
  @mock.close_mock_query_issuer(issuer)
  assert_true(
    @mock.verify_mock_query_records(issuer, broad, second) is Err(IssuerClosed),
  )
  assert_true(
    @mock.prepare_issued_mock_query_attempt(
      issuer,
      strategy_for(sequence, @mock.NativeQuery),
      [],
      0,
    )
    is Err(IssuerClosed),
  )
}

///|
test "mock evidence issuance is atomic under serialization limits" {
  let (issuer, sequence) = query_issuer_fixture()
  let reference = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
  query_issuer_run(reference)
  let baseline = @mock.issue_mock_query_records(
    reference,
    query_material_limits(),
  ).unwrap()
  let (bytes, nodes) = @mock.mock_query_record_usage(baseline)
  for short in [false, true] {
    let attempt = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
    query_issuer_run(attempt)
    let result = @mock.issue_mock_query_records(attempt, {
      ..query_material_limits(),
      max_bytes: bytes - (if short { 1 } else { 0 }),
      max_nodes: nodes,
    })
    if short {
      assert_true(result is Err(Encoding(_)))
      assert_true(
        @mock.mock_query_computation(attempt) is Err(Evidence(Encoding(_))),
      )
      assert_true(
        @mock.issue_mock_query_records(attempt, query_material_limits())
        is Err(NotRetained),
      )
    } else {
      assert_true(result is Ok(_))
    }
  }
}

///|
test "closed issuer stops pending dispatch and failed retention emits no records" {
  let (issuer, sequence) = query_issuer_fixture()
  let failed = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
  @mock.execute_mock_query(
    failed,
    mock_strategy_limits(),
    guard_measure=Some(query_guard_physical()),
  ).unwrap()
  |> ignore
  assert_true(
    @mock.retain_mock_query(failed, {
      ..query_retention_limits(),
      retained_wire_bytes: 0,
    })
    is Err(RetainedBytes),
  )
  assert_true(
    @mock.issue_mock_query_records(failed, query_material_limits())
    is Err(NotRetained),
  )
  let pending = query_issuer_attempt(issuer, sequence, @mock.NativeQuery)
  @mock.close_mock_query_issuer(issuer)
  assert_true(
    @mock.execute_mock_query(
      pending,
      mock_strategy_limits(),
      guard_measure=Some(query_guard_physical()),
    )
    is Err(Evidence(IssuerClosed)),
  )
}
