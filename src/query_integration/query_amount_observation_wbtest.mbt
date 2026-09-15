///|
fn query_amount_setup(
  nullable : Bool,
  ceiling? : Int = 100,
) -> (@query.QuerySequence, @planning.QueryRequirement, @mock.MockQueryIssuer) raise {
  let checked = query_checked_program_fixture(
    catalog=Some(
      if nullable {
        query_amount_nullable_catalog()
      } else {
        query_amount_required_catalog()
      },
    ),
  )
  let sequence = query_checked_sequence(checked)
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 10, max_value_bytes: ceiling, },
    query_material_limits(),
  ).unwrap()
  let (a, e) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    a,
    e,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "amount-oracle", 100,
  ).unwrap()
  (sequence, requirement, issuer)
}

///|
fn query_observation_member(
  text : String,
  section : String,
  field_name : String,
) -> String raise {
  guard @json.parse(text) is Object(root) else { fail("observation") }
  guard root.get(section) is Some(Object(fields)) else { fail("section") }
  fields.get(field_name).unwrap().stringify()
}

///|
test "unused amount changes broad access but not native receipt or consumer output" {
  let (sequence, requirement, issuer) = query_amount_setup(true)
  let owner = @query.query_sequence_owner(sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let selected = "[{\"id\":3},{\"id\":3},{\"id\":2}]"
  let sources = [
    "[{\"amount\":10,\"id\":3},{\"amount\":null,\"id\":1},{\"amount\":20,\"id\":3},{\"amount\":30,\"id\":2}]",
    "[{\"amount\":11,\"id\":3},{\"amount\":null,\"id\":1},{\"amount\":20,\"id\":3},{\"amount\":30,\"id\":2}]",
  ]
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let native = route == @mock.NativeQuery
    let received_fields = if native {
      "[\"id\"]"
    } else {
      "[\"amount\",\"id\"]"
    }
    let mut prior_scope : String? = None
    for source in sources {
      let rows = input_cursor(source)
      let attempt = @mock.prepare_issued_mock_query_attempt(
        issuer,
        strategy_for(sequence, route),
        Array::makei(4, i => @decode.element_at(rows, i).unwrap()),
        4,
      ).unwrap()
      // Expectations use literal source/selected rows and explicit received
      // columns, never the emitted access record or computed result.
      let (expected, cids) = query_observation_oracle(
        requirement,
        @mock.mock_query_attempt_identity(attempt).unwrap(),
        if native {
          selected
        } else {
          source
        },
        if native {
          3
        } else {
          4
        },
        received_fields,
        selected,
        3,
      )
      @mock.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      ).unwrap()
      |> ignore
      @mock.retain_mock_query(attempt, {
        received_wire_bytes: 100000,
        retained_wire_bytes: 100000,
        measurement: row_wire_limits(),
      }).unwrap()
      |> ignore
      let records = @mock.issue_mock_query_records(
        attempt,
        query_material_limits(),
      ).unwrap()
      for i in 0..<3 {
        assert_eq(@mock.mock_query_record_at(records, i).unwrap().1, cids[i])
      }
      let observation = @mock.capture_mock_query(
        issuer,
        attempt,
        records,
        query_capture_limits(),
      ).unwrap()
      let text = @encode.document_text(
        @mock.mock_query_observation_document(observation),
      )
      assert_eq(text, expected)
      assert_eq(
        @mock.mock_query_observation_cid(observation),
        query_material_expected(expected),
      )
      assert_eq(
        query_observation_member(text, "actual_access", "received_fields"),
        received_fields,
      )
      assert_eq(
        query_observation_member(text, "output", "rows_cid"),
        query_oracle_quote(query_material_expected(selected)),
      )
      let scope = query_observation_member(text, "actual_access", "scope_cid")
      if prior_scope is Some(prior) {
        assert_eq(prior == scope, native)
      }
      prior_scope = Some(scope)
      let input = @mock.bind_captured_query_input(
        issuer, attempt, observation, receiver, 0, owner,
      ).unwrap()
      let consumer = @execution.prepare_local_compute_attempt(
        compute_test_sequence(receiver),
        [input],
        3,
      ).unwrap()
      let output = @execution.completed_output(
        @execution.execute_local_compute_attempt(
          consumer,
          compute_test_limits(),
        ).unwrap(),
        Step(0),
      ).unwrap()
      assert_eq(@execution.completed_row_count(output), 3)
      assert_eq(
        @execution.row_wire_cid(
          @execution.identify_completed_rows(output, row_wire_limits()).unwrap(),
        ),
        query_material_expected(selected),
      )
    }
  }
}

///|
test "filtered-out unused amount still requires type nullability and value guard admission" {
  for
    (nullable, source, guard_failure) in [
      (true, "{\"amount\":\"wrong\",\"id\":0}", false),
      (false, "{\"amount\":null,\"id\":0}", false),
      (false, "{\"amount\":123456,\"id\":0}", true),
    ] {
    let (sequence, _, issuer) = query_amount_setup(nullable, ceiling=5)
    for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
      let attempt = @mock.prepare_issued_mock_query_attempt(
        issuer,
        strategy_for(sequence, route),
        [input_cursor(source)],
        1,
      ).unwrap()
      let result = @mock.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      )
      if guard_failure {
        assert_true(result is Err(Guard(ValueBytes(Scan, 0, -1))))
      } else {
        assert_true(result is Err(Local(ReceiptAdmission(_))))
      }
      assert_true(
        @mock.retain_mock_query(attempt, query_retention_limits())
        is Err(NotAwaitingCapture),
      )
      assert_true(
        @mock.issue_mock_query_records(attempt, query_material_limits())
        is Err(NotRetained),
      )
      // No issued record handle exists, so capture cannot be called for this
      // failed task. Execution is one-shot and never retries as the other route.
      assert_true(
        @mock.execute_mock_query(attempt, mock_strategy_limits())
        is Err(AlreadyStarted),
      )
    }
  }
}
