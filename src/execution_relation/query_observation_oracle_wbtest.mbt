///|
fn query_oracle_quote(text : String) -> String {
  text.to_json().stringify()
}

///|
// Independent object assembly from the static requirement and fixed rows.
// Neither product record/observation output nor their emitters are oracle input.
fn query_observation_oracle(
  requirement : @planning.QueryRequirement,
  ids : (String, String),
  received : String,
  received_count : Int,
  output : String,
  output_count : Int,
) -> (String, Array[String]) raise {
  guard @json.parse(
      @encode.document_text(@planning.query_requirement_document(requirement)),
    )
    is Object(fields) else {
    abort("requirement object")
  }
  let requirement_cid = query_material_expected(
    @encode.document_text(@planning.query_requirement_document(requirement)),
  )
  let request_cid = query_material_expected(
    fields.get("request").unwrap().stringify(),
  )
  let scope_cid = query_material_expected(
    "{\"version\":\"actql-query-scan-scope/0.1\",\"source_ref\":" +
    fields.get("source_ref").unwrap().stringify() +
    ",\"source_contract_cid\":" +
    fields.get("source_contract_cid").unwrap().stringify() +
    ",\"resolved_request_cid\":" +
    query_oracle_quote(request_cid) +
    "}",
  )
  let access_cid = query_material_expected(
    "{\"version\":\"actql-query-access-scope/0.1\",\"requirement_cid\":" +
    query_oracle_quote(requirement_cid) +
    ",\"received_fields\":[\"id\"],\"received_rows_cid\":" +
    query_oracle_quote(query_material_expected(received)) +
    "}",
  )
  // These fixed rows contain only ASCII numeric/null JSON; their literal length
  // is independently the canonical UTF-8 wire byte length, including brackets.
  let access = "{\"scope_cid\":" +
    query_oracle_quote(access_cid) +
    ",\"provider_scope_cid\":null,\"received_fields\":[\"id\"],\"received_rows\":" +
    received_count.to_string() +
    ",\"received_bytes\":" +
    received.length().to_string() +
    "}"
  let result = "{\"contract_cid\":" +
    fields.get("output_contract_cid").unwrap().stringify() +
    ",\"rows_cid\":" +
    query_oracle_quote(query_material_expected(output)) +
    ",\"row_count\":" +
    output_count.to_string() +
    "}"
  let records : Array[String] = []
  for role in ["source_validation", "filter", "select"] {
    records.push(
      query_material_expected(
        "{\"version\":\"actql-query-process-evidence/0.1\",\"issuer\":" +
        query_oracle_quote(ids.0) +
        ",\"attempt\":" +
        query_oracle_quote(ids.1) +
        ",\"requirement_cid\":" +
        query_oracle_quote(requirement_cid) +
        ",\"role\":" +
        query_oracle_quote(role) +
        ",\"snapshot\":null,\"scan_scope_cid\":" +
        query_oracle_quote(scope_cid) +
        ",\"actual_access\":" +
        access +
        ",\"output\":" +
        result +
        "}",
      ),
    )
  }
  let observation = "{\"version\":\"actql-query-observation/0.1\",\"requirement_cid\":" +
    query_oracle_quote(requirement_cid) +
    ",\"owner\":" +
    fields.get("owner").unwrap().stringify() +
    ",\"source_ref\":" +
    fields.get("source_ref").unwrap().stringify() +
    ",\"source_contract_cid\":" +
    fields.get("source_contract_cid").unwrap().stringify() +
    ",\"parameter_values_cid\":" +
    fields.get("parameter_values_cid").unwrap().stringify() +
    ",\"resolved_request_cid\":" +
    query_oracle_quote(request_cid) +
    ",\"snapshot\":null,\"actual_access\":" +
    access +
    ",\"coverage\":{\"scope_cid\":" +
    query_oracle_quote(scope_cid) +
    ",\"complete\":true,\"source_validation_evidence_cid\":" +
    query_oracle_quote(records[0]) +
    ",\"filter_evidence_cid\":" +
    query_oracle_quote(records[1]) +
    ",\"select_evidence_cid\":" +
    query_oracle_quote(records[2]) +
    "},\"output\":" +
    result +
    ",\"retention\":\"process\"}"
  (
    @identity.stringify_value(
      @identity.from_json(@json.parse(observation), 10000, 100, 100000),
      100000,
      10000,
      100,
    ),
    records,
  )
}

///|
test "entire captured observation matches independent source rows oracle" {
  query_observation_oracle_cases(false)
  query_observation_oracle_cases(true)
}

///|
fn query_observation_oracle_cases(nullable : Bool) -> Unit raise {
  let checked = query_checked_program_fixture(nullable~)
  let sequence = query_checked_sequence(checked)
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let (a, e) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    a,
    e,
    query_capture_limits(),
  ).unwrap()
  let issuer = @planning.prepare_mock_query_issuer(
    contracts, requirement, "oracle-process", 100,
  ).unwrap()
  let owner = @lower.sequence_owner(sequence.generated.sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let cases = [
    (
      "[{\"id\":3},{\"id\":1},{\"id\":3},{\"id\":2}]", "[{\"id\":3},{\"id\":3},{\"id\":2}]",
      4, 3,
    ),
    ("[]", "[]", 0, 0),
    ("[{\"id\":1},{\"id\":0}]", "[]", 2, 0),
  ]
  if nullable {
    cases.push(
      (
        "[{\"id\":null},{\"id\":3},{\"id\":null},{\"id\":2}]", "[{\"id\":3},{\"id\":2}]",
        4, 2,
      ),
    )
    cases.push(("[{\"id\":null},{\"id\":null}]", "[]", 2, 0))
  }
  for (source, selected, before, after) in cases {
    let rows = input_cursor(source)
    let inputs = Array::makei(before, i => @decode.element_at(rows, i).unwrap())
    for route in [@planning.NativeQuery, @planning.BroadWithResidual] {
      let attempt = @planning.prepare_issued_mock_query_attempt(
        issuer,
        strategy_for(sequence, route),
        inputs,
        before,
      ).unwrap()
      let ids = @planning.mock_query_attempt_identity(attempt).unwrap()
      let (expected, expected_records) = query_observation_oracle(
        requirement,
        ids,
        if route == @planning.NativeQuery {
          selected
        } else {
          source
        },
        if route == @planning.NativeQuery {
          after
        } else {
          before
        },
        selected,
        after,
      )
      @planning.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      ).unwrap()
      |> ignore
      @planning.retain_mock_query(attempt, {
        received_wire_bytes: 100000,
        retained_wire_bytes: 100000,
        measurement: row_wire_limits(),
      }).unwrap()
      |> ignore
      let records = @planning.issue_mock_query_records(
        attempt,
        query_material_limits(),
      ).unwrap()
      for i in 0..<3 {
        assert_eq(
          @planning.mock_query_record_at(records, i).unwrap().1,
          expected_records[i],
        )
      }
      let observation = @planning.capture_mock_query(
        issuer,
        attempt,
        records,
        query_capture_limits(),
      ).unwrap()
      assert_eq(
        @encode.document_text(
          @planning.mock_query_observation_document(observation),
        ),
        expected,
      )
      assert_eq(
        @planning.mock_query_observation_cid(observation),
        query_material_expected(expected),
      )
      let input = @planning.bind_captured_query_input(
        issuer, attempt, observation, receiver, 0, owner,
      ).unwrap()
      let consumer = prepare_local_compute_attempt(
        compute_test_sequence(receiver),
        [input],
        3, // One inventory entry, membership entry and owned input handle.
      ).unwrap()
      let complete = execute_local_compute_attempt(
        consumer,
        compute_test_limits(),
      ).unwrap()
      let output = completed_output(complete, Step(0)).unwrap()
      assert_eq(completed_row_count(output), after)
      assert_eq(
        row_wire_cid(
          identify_completed_rows(output, row_wire_limits()).unwrap(),
        ),
        query_material_expected(selected),
      )
    }
  }
}
