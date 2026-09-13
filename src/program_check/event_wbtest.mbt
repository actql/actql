///|
test "formal Event paths close admission selection and output envelopes through Result imports" {
  for
    kind in ["bridge", "mark", "drop", "dedupe", "session", "relation_session"] {
    let operation = match kind {
      "bridge" => ""
      "mark" | "drop" =>
        "{\"watermark_events\":{\"watermark_ms\":10,\"policy\":\"" +
        kind +
        "\"}},"
      "dedupe" =>
        "{\"dedupe_events\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"value\":\"asc\"}]}},"
      "session" => "{\"session\":{\"by\":[],\"gap\":{\"$param\":\"n\"}}},"
      _ =>
        "{\"session\":{\"id\":\"id\",\"time\":\"value\",\"by\":[],\"gap\":{\"$param\":\"n\"}}},"
    }
    let event_carrier = kind != "relation_session"
    let steps = "[" +
      (if event_carrier {
        "{\"to_events\":{\"id\":\"id\",\"time\":\"value\"}},"
      } else {
        ""
      }) +
      operation +
      (if event_carrier { "{\"events\":true}," } else { "" }) +
      "{\"take\":1},{\"select\":[\"id\",\"value\"],\"as\":\"selected\"}]"
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      parameters=true,
      tea=true,
      second_steps=steps,
      second_result_from="selected",
      extra_step_budget=5,
    )
    assert_eq(checked.length(), 1)
    let program = checked[0]
    assert_eq(unit_count(program), 2)
    assert_true(
      unit_definition_cid(program, 0) != unit_definition_cid(program, 1),
    )
    assert_eq(unit_publication_count(program, 1), Some(1))
    let pipeline = unit_pipeline(program, 1).unwrap()
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut envelopes = 0
    let mut admissions = 0
    let mut sessions = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(check)) else {
        continue
      }
      match check {
        EventEnvelope(envelope) => {
          envelopes += 1
          assert_eq(envelope.site.stage, 1)
          assert_true(physical_equal(envelope.site.pipeline, pipeline))
          assert_eq(
            @policy.ceiling_field(envelope.ceiling),
            if event_carrier {
              "max_temporal_output_rows"
            } else {
              "max_relation_output_rows"
            },
          )
          assert_eq(
            @context.operation_execution_phase(check),
            BeforeOperationOutput,
          )
        }
        EventExecution(event) => {
          admissions += 1
          assert_true(physical_equal(event.site.pipeline, pipeline))
          assert_eq(event.site.stage, 1)
        }
        SessionExecution(session) => {
          sessions += 1
          assert_true(physical_equal(session.site.pipeline, pipeline))
          assert_eq(session.gap_ms, 1L)
          assert_true(session.gap_resolution is Some(_))
        }
        _ => ()
      }
    }
    assert_eq(envelopes, if kind == "bridge" || !event_carrier { 1 } else { 2 })
    assert_true(admissions >= 2)
    assert_eq(sessions, if kind == "session" || !event_carrier { 2 } else { 0 })
  }
}

///|
test "formal Event validation remains required for empty and duplicate generated rows" {
  for rows in ["[]", "[{\"id\":1},{\"id\":1}]"] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      tea=true,
      generated_rows=Some(rows),
      local_primary_key=false,
      producer_suffix=",{\"to_events\":{\"id\":\"id\",\"time\":\"value\"}},{\"events\":true,\"as\":\"selected\"}",
      producer_result_from="selected",
      extra_step_budget=2,
    )
    let program = programs[0]
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut identities = 0
    let mut admission = 0
    let mut envelopes = 0
    for i in 0..<@context.operation_closure_count(closure) {
      match @context.operation_closure_at(closure, i) {
        Some(ExecutionCheck(EventExecution(check))) => {
          assert_eq(check.site.stage, 0)
          assert_eq(check.site.step, 2)
          match check.rule {
            ValidateEventIdentities => identities += 1
            AdmitEventValues => admission += 1
            _ => ()
          }
        }
        Some(ExecutionCheck(EventEnvelope(_))) => envelopes += 1
        _ => ()
      }
    }
    assert_eq(identities, 1)
    assert_eq(admission, 1)
    assert_eq(envelopes, 1)
    assert_eq(unit_publication_count(program, 0), Some(1))
  }
}

///|
test "formal session rejects invalid bound gaps before exposing any later Stage" {
  for value in ["0", "-1", "0.5", "9007199254740992"] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=programs,
        tea=true,
        second_stage=true,
        parameters=true,
        supplied=Some(supplied_fixture("{\"n\":" + value + "}")),
        second_steps="[{\"session\":{\"id\":\"id\",\"time\":\"value\",\"by\":[],\"gap\":{\"$param\":\"n\"}},\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=1,
      )
    catch {
      Closure(
        Operations(
          Scalars(InvalidValue(_, @pipeline.Milliseconds("n", signed=false)))
        )
      ) => ()
      error => raise error
    } noraise {
      _ => fail("invalid bound gap accepted")
    }
    assert_true(programs.is_empty())
  }
}
