///|
priv struct NativeIssuerFixture {
  issuer : @duckdb_query.DuckDBNativeIssuer
  requirement : @planning.QueryRequirement
  choice : @planning.AcquisitionChoice
  candidate : @planning.PreparedAcquisition[
    @duckdb_query.DuckDBNativePreparation,
  ]
  transport : Array[@duckdb_query.DuckDBNativeAttempt]
}

///|
fn native_issuer_fixture() -> NativeIssuerFixture raise {
  let (registry, requirement, prepared) = native_candidate_fixture()
  let candidate = @duckdb_query.duckdb_native_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    prepared,
    [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        milliseconds: Some(10L),
      },
    ],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("native choice")
  }
  let (query, evidence) = query_evidence_test_bodies()
  let dependencies = @planning.admit_query_evidence_contracts(
    query,
    evidence,
    query_capture_limits(),
  ).unwrap()
  let contract = @planning.admit_query_two_receipt_contract(
    dependencies,
    query_two_receipt_test_body(),
    query_capture_limits(),
  ).unwrap()
  // Portable Host double only. Real Node must bind both receipts, one exact
  // grant/port/read view and successful session settlement instead of this set.
  let transport : Array[@duckdb_query.DuckDBNativeAttempt] = []
  let issuer = @duckdb_query.prepare_duckdb_native_issuer(
    contract,
    requirement,
    "portable-native",
    100,
    attempt => transport.any(value => physical_equal(value, attempt)),
  ).unwrap()
  { issuer, requirement, choice, candidate, transport, }
}

///|
fn native_issued_attempt(
  f : NativeIssuerFixture,
) -> @duckdb_query.DuckDBNativeAttempt {
  @duckdb_query.prepare_issued_duckdb_native_attempt(
    f.issuer,
    f.choice,
    f.candidate,
    { max_rows: 5, max_cells: 5, max_nodes: 5, max_text_bytes: 0, },
    100,
    native_demand_physical(),
  ).unwrap()
}

///|
fn native_issued_run(
  f : NativeIssuerFixture,
  attempt : @duckdb_query.DuckDBNativeAttempt,
) -> Unit {
  native_attempt_receive_fixture(attempt)
  @duckdb_query.settle_duckdb_native_transport(attempt).unwrap()
  @duckdb_query.measure_duckdb_native_attempt(
    attempt,
    native_demand_physical(),
    native_attempt_wire(),
    5,
    47,
  ).unwrap()
  |> ignore
  f.transport.push(attempt)
}

///|
test "two-receipt contract admits only the full pin under cumulative dependency limits" {
  let (query, evidence) = query_evidence_test_bodies()
  let dependencies = @planning.admit_query_evidence_contracts(
    query,
    evidence,
    query_capture_limits(),
  ).unwrap()
  let body = query_two_receipt_test_body()
  // Independent canonical JSON UTF-8 lengths and JSON node counts of the three
  // shared input files, not product verifier usage used as expected values.
  let exact : @planning.QueryEvidenceLimits = {
    max_bytes: 17588,
    max_nodes: 764,
    max_depth: 100,
  }
  let contract = @planning.admit_query_two_receipt_contract(
    dependencies, body, exact,
  ).unwrap()
  assert_eq(@planning.query_two_receipt_contract_usage(contract), (17588, 764))
  for limits in [{ ..exact, max_bytes: 17587, }, { ..exact, max_nodes: 763, }] {
    assert_true(
      @planning.admit_query_two_receipt_contract(dependencies, body, limits)
      is Err(EvidenceBodyLimit),
    )
  }
  assert_true(
    @planning.admit_query_two_receipt_contract(dependencies, evidence, exact)
    is Err(UnsupportedEvidence),
  )
  assert_true(
    @planning.admit_query_two_receipt_contract(dependencies, body, {
      ..exact,
      max_bytes: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
fn native_oracle_nodes(text : String) -> Int raise {
  let pending = [@json.parse(text)]
  let mut count = 0
  while pending.length() > 0 {
    let value = pending.pop().unwrap()
    count += 1
    match value {
      Array(items) =>
        for item in items {
          pending.push(item)
        }
      Object(fields) =>
        for (_, item) in fields {
          pending.push(item)
        }
      _ => ()
    }
  }
  count
}

///|
test "native artifact accounting spans both receipts three records and capture at exact bounds" {
  for shortage in [0, 1, 2] {
    let f = native_issuer_fixture()
    let attempt = native_issued_attempt(f)
    native_issued_run(f, attempt)
    let (receipts, records, observation) = native_observation_oracle(
      f.requirement,
      @duckdb_query.duckdb_native_attempt_identity(attempt).unwrap(),
    )
    guard @json.parse(
        @encode.document_text(
          @planning.query_requirement_document(f.requirement),
        ),
      )
      is Object(req) else {
      abort("req")
    }
    let request = req.get("request").unwrap().stringify()
    let scope = "{\"version\":\"actql-query-scan-scope/0.1\",\"source_ref\":" +
      req.get("source_ref").unwrap().stringify() +
      ",\"source_contract_cid\":" +
      req.get("source_contract_cid").unwrap().stringify() +
      ",\"resolved_request_cid\":" +
      query_oracle_quote(query_material_expected(request)) +
      "}"
    // All fixed fixture JSON is ASCII. Key ordering does not change lengths or
    // node counts. Document construction plus hashing charges each artifact twice.
    let mut bytes = scope.length() + request.length() + 2 * observation.length()
    let mut nodes = native_oracle_nodes(scope) +
      native_oracle_nodes(request) +
      2 * native_oracle_nodes(observation)
    for group in [receipts, records] {
      for text in group {
        bytes += 2 * text.length()
        nodes += 2 * native_oracle_nodes(text)
      }
    }
    let issued = @duckdb_query.issue_duckdb_native_records(
      attempt,
      47,
      query_material_limits(),
    ).unwrap()
    let captured = @duckdb_query.capture_duckdb_native_query(
      f.issuer,
      attempt,
      issued,
      {
        max_bytes: bytes - (if shortage == 1 { 1 } else { 0 }),
        max_nodes: nodes - (if shortage == 2 { 1 } else { 0 }),
        max_depth: 100,
      },
    )
    if shortage == 0 {
      assert_eq(
        @duckdb_query.duckdb_native_observation_usage(captured.unwrap()),
        (bytes, nodes),
      )
    } else {
      assert_true(captured is Err(Encoding(OutputLimit)))
      assert_true(
        @duckdb_query.verify_duckdb_native_records(f.issuer, attempt, issued)
        is Err(ForeignRecords),
      )
    }
  }
}

///|
// Independent JSON assembly, no product receipt, record, observation or returned
// source data is an oracle input. Rows and byte counts are fixed below.
fn native_observation_oracle(
  requirement : @planning.QueryRequirement,
  ids : (String, String, String),
) -> (Array[String], Array[String], String) raise {
  guard @json.parse(
      @encode.document_text(@planning.query_requirement_document(requirement)),
    )
    is Object(req) else {
    abort("requirement")
  }
  let request = req.get("request").unwrap().stringify()
  let requirement_cid = query_material_expected(
    @encode.document_text(@planning.query_requirement_document(requirement)),
  )
  let scope = query_material_expected(
    "{\"version\":\"actql-query-scan-scope/0.1\",\"source_ref\":" +
    req.get("source_ref").unwrap().stringify() +
    ",\"source_contract_cid\":" +
    req.get("source_contract_cid").unwrap().stringify() +
    ",\"resolved_request_cid\":" +
    query_oracle_quote(query_material_expected(request)) +
    "}",
  )
  let common = "\"issuer\":" +
    query_oracle_quote(ids.0) +
    ",\"attempt\":" +
    query_oracle_quote(ids.1) +
    ",\"read_view\":" +
    query_oracle_quote(ids.2) +
    ",\"requirement_cid\":" +
    query_oracle_quote(requirement_cid) +
    ",\"snapshot\":null,\"scan_scope_cid\":" +
    query_oracle_quote(scope)
  let receipts = []
  for
    (role, rows, count, bytes) in [
      ("validation_scan", "[{\"id\":3},{\"id\":1},{\"id\":2}]", 3, 28),
      ("native_result", "[{\"id\":3},{\"id\":2}]", 2, 19),
    ] {
    receipts.push(
      "{\"version\":\"actql-query-receipt/0.1\"," +
      common +
      ",\"role\":" +
      query_oracle_quote(role) +
      ",\"received_rows_cid\":" +
      query_oracle_quote(query_material_expected(rows)) +
      ",\"received_rows\":" +
      count.to_string() +
      ",\"received_fields\":[\"id\"],\"received_bytes\":" +
      bytes.to_string() +
      "}",
    )
  }
  let accesses = "{\"validation_scan_cid\":" +
    query_oracle_quote(query_material_expected(receipts[0])) +
    ",\"native_result_cid\":" +
    query_oracle_quote(query_material_expected(receipts[1])) +
    "}"
  let output = "{\"contract_cid\":" +
    req.get("output_contract_cid").unwrap().stringify() +
    ",\"rows_cid\":" +
    query_oracle_quote(query_material_expected("[{\"id\":3},{\"id\":2}]")) +
    ",\"row_count\":2}"
  let records = []
  for role in ["source_validation", "filter", "select"] {
    records.push(
      "{\"version\":\"actql-query-two-receipt-evidence/0.1\"," +
      common +
      ",\"role\":" +
      query_oracle_quote(role) +
      ",\"accesses\":" +
      accesses +
      ",\"output\":" +
      output +
      "}",
    )
  }
  let observation = "{\"version\":\"actql-query-two-receipt-observation/0.1\",\"evidence_contract_cid\":\"sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8\",\"requirement_cid\":" +
    query_oracle_quote(requirement_cid) +
    ",\"owner\":" +
    req.get("owner").unwrap().stringify() +
    ",\"source_ref\":" +
    req.get("source_ref").unwrap().stringify() +
    ",\"source_contract_cid\":" +
    req.get("source_contract_cid").unwrap().stringify() +
    ",\"parameter_values_cid\":" +
    req.get("parameter_values_cid").unwrap().stringify() +
    ",\"resolved_request_cid\":" +
    query_oracle_quote(query_material_expected(request)) +
    ",\"snapshot\":null,\"execution\":{\"issuer\":" +
    query_oracle_quote(ids.0) +
    ",\"attempt\":" +
    query_oracle_quote(ids.1) +
    ",\"read_view\":" +
    query_oracle_quote(ids.2) +
    "},\"accesses\":" +
    accesses +
    ",\"coverage\":{\"scope_cid\":" +
    query_oracle_quote(scope) +
    ",\"complete\":true,\"source_validation_evidence_cid\":" +
    query_oracle_quote(query_material_expected(records[0])) +
    ",\"filter_evidence_cid\":" +
    query_oracle_quote(query_material_expected(records[1])) +
    ",\"select_evidence_cid\":" +
    query_oracle_quote(query_material_expected(records[2])) +
    "},\"output\":" +
    output +
    ",\"retention\":\"process\"}"
  (receipts, records, observation)
}

///|
test "native Host-local two-receipt issuance and capture match an independent observation oracle" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  native_issued_run(f, attempt)
  let records = @duckdb_query.issue_duckdb_native_records(
    attempt,
    47,
    query_material_limits(),
  ).unwrap()
  let (expected_receipts, expected_records, expected_observation) = native_observation_oracle(
    f.requirement,
    @duckdb_query.duckdb_native_attempt_identity(attempt).unwrap(),
  )
  for i in 0..<2 {
    let (document, cid) = @duckdb_query.duckdb_native_receipt_at(records, i).unwrap()
    assert_eq(cid, query_material_expected(expected_receipts[i]))
    assert_eq(
      @json.parse(@encode.document_text(document)),
      @json.parse(expected_receipts[i]),
    )
  }
  for i in 0..<3 {
    let (document, cid) = @duckdb_query.duckdb_native_record_at(records, i).unwrap()
    assert_eq(cid, query_material_expected(expected_records[i]))
    assert_eq(
      @json.parse(@encode.document_text(document)),
      @json.parse(expected_records[i]),
    )
  }
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      attempt,
      47,
      query_material_limits(),
    )
    is Err(NotRetained),
  )
  let observation = @duckdb_query.capture_duckdb_native_query(
    f.issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  assert_eq(
    @duckdb_query.duckdb_native_observation_cid(observation),
    query_material_expected(expected_observation),
  )
  assert_eq(
    @json.parse(
      @encode.document_text(
        @duckdb_query.duckdb_native_observation_document(observation),
      ),
    ),
    @json.parse(expected_observation),
  )
  assert_true(
    @duckdb_query.capture_duckdb_native_query(
      f.issuer,
      attempt,
      records,
      query_capture_limits(),
    )
    is Err(AlreadyCaptured),
  )
  @duckdb_query.abort_duckdb_native_attempt(attempt)
  @duckdb_query.verify_duckdb_native_observation(f.issuer, attempt, observation).unwrap()
  f.transport.clear()
  assert_true(
    @duckdb_query.verify_duckdb_native_observation(
      f.issuer,
      attempt,
      observation,
    )
    is Err(UnverifiedTransport),
  )
  @duckdb_query.close_duckdb_native_issuer(f.issuer)
  assert_true(
    @duckdb_query.verify_duckdb_native_records(f.issuer, attempt, records)
    is Err(IssuerClosed),
  )
}

///|
test "native records reject unissued unverified cancelled foreign and incompletely retained attempts" {
  let f = native_issuer_fixture()
  let unissued = native_selected_attempt()
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      unissued,
      47,
      query_material_limits(),
    )
    is Err(UnauthorizedAttempt),
  )
  let early = native_issued_attempt(f)
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      early,
      47,
      query_material_limits(),
    )
    is Err(NotRetained),
  )
  @duckdb_query.abort_duckdb_native_attempt(early)
  assert_true(
    @duckdb_query.settle_duckdb_native_transport(early) is Err(InvalidState),
  )
  let unverified = native_issued_attempt(f)
  native_issued_run(f, unverified)
  f.transport.clear()
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      unverified,
      47,
      query_material_limits(),
    )
    is Err(UnverifiedTransport),
  )
  f.transport.push(unverified)
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      unverified,
      47,
      query_material_limits(),
    )
    is Err(NotRetained),
  )
  let short = native_issued_attempt(f)
  native_issued_run(f, short)
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      short,
      46,
      query_material_limits(),
    )
    is Err(Encoding(OutputLimit)),
  )
  assert_true(
    @duckdb_query.issue_duckdb_native_records(
      short,
      47,
      query_material_limits(),
    )
    is Err(NotRetained),
  )
  let good = native_issued_attempt(f)
  native_issued_run(f, good)
  let records = @duckdb_query.issue_duckdb_native_records(
    good,
    47,
    query_material_limits(),
  ).unwrap()
  let foreign = native_issuer_fixture()
  assert_true(
    @duckdb_query.verify_duckdb_native_records(foreign.issuer, good, records)
    is Err(UnauthorizedAttempt),
  )
  let another = native_issued_attempt(f)
  native_issued_run(f, another)
  assert_true(
    @duckdb_query.verify_duckdb_native_records(f.issuer, another, records)
    is Err(UnauthorizedAttempt),
  )
  assert_true(
    @duckdb_query.capture_duckdb_native_query(f.issuer, good, records, {
      ..query_capture_limits(),
      max_bytes: 0,
    })
    is Err(Encoding(OutputLimit)),
  )
  assert_true(
    @duckdb_query.capture_duckdb_native_query(
      f.issuer,
      good,
      records,
      query_capture_limits(),
    )
    is Err(ForeignRecords),
  )
}
