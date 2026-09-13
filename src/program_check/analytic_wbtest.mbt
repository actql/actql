///|
test "formal analytic ranking and navigation retain owned demands and envelopes across Result imports" {
  for
    (function, frame, nullable) in [
      ("{\"fn\":\"row_number\"}", "", false),
      ("{\"fn\":\"rank\"}", "", false),
      ("{\"fn\":\"dense_rank\"}", "", false),
      ("{\"fn\":\"lag\",\"expr\":\"value\",\"offset\":0}", "", true),
      (
        "{\"fn\":\"lead\",\"expr\":\"value\",\"offset\":{\"$param\":\"n\"}}", "",
        true,
      ),
      (
        "{\"fn\":\"first_value\",\"expr\":\"value\"}", ",\"frame\":{\"start\":\"current_row\",\"end\":\"current_row\"}",
        true,
      ),
      (
        "{\"fn\":\"last_value\",\"expr\":\"value\"}", ",\"frame\":{\"start\":{\"following\":1},\"end\":{\"following\":2}}",
        true,
      ),
      (
        "{\"fn\":\"count\",\"expr\":\"value / 0\",\"filter\":\"FALSE\"}", ",\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"}",
        false,
      ),
      (
        "{\"fn\":\"min\",\"field\":\"value\"}", ",\"frame\":{\"start\":\"current_row\",\"end\":\"current_row\"}",
        true,
      ),
    ] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      second_stage=true,
      parameters=true,
      analytic_limit=Some(1000),
      checked_results=checked,
      producer_suffix=",{\"analytic\":{\"partition_by\":[\"id\",\"id\"],\"order_by\":[{\"value\":\"desc\"}],\"functions\":{\"answer\":" +
        function +
        "}" +
        frame +
        "}},{\"select\":[\"id\",{\"value\":\"answer\"}],\"as\":\"selected\"}",
      producer_result_from="selected",
      extra_step_budget=3,
    )
    assert_eq(checked.length(), 1)
    let program = checked[0]
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut demand = 0
    let mut envelopes = 0
    let mut imported = 0
    for i in 0..<@context.operation_closure_count(closure) {
      match @context.operation_closure_at(closure, i) {
        Some(ExecutionCheck(AnalyticExecution(check))) => {
          assert_true(
            physical_equal(
              check.site.pipeline,
              unit_pipeline(program, 0).unwrap(),
            ),
          )
          assert_eq(check.site.step, 1)
          assert_eq(check.input, @pipeline.Step(0))
          assert_eq(@relation.analytic_partition_count(check.analytic), 2)
          let call = @relation.analytic_call_at(check.analytic, 0).unwrap()
          assert_eq(call.name, "answer")
          assert_eq(call.result.nullable, nullable)
          assert_true(call.result.shape is @contract.Number)
          if check.rule is EvaluateCallDemands {
            demand += 1
          }
          if check.site.stage != 0 {
            imported += 1
          }
        }
        Some(ExecutionCheck(AnalyticEnvelope(check))) => {
          envelopes += 1
          assert_true(
            physical_equal(
              check.site.pipeline,
              unit_pipeline(program, 0).unwrap(),
            ),
          )
          assert_eq(@policy.ceiling_value(check.input_wire_bytes), 1000L)
          assert_eq(@policy.ceiling_value(check.partition_wire_bytes), 1000L)
          assert_eq(@policy.ceiling_value(check.frame_memberships), 1000L)
        }
        _ => ()
      }
    }
    assert_true(demand > 1)
    assert_eq(envelopes, demand)
    assert_true(imported > 0)
  }
}

///|
test "formal analytic distinguishes missing position evidence from authored values order" {
  for
    (function, generated, accepted) in [
      ("rank", false, true),
      ("row_number", false, false),
      ("row_number", true, true),
    ] {
    let checked : Array[CheckedProgram] = []
    try {
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        analytic_limit=Some(1000),
        checked_results=checked,
        local_primary_key=false,
        generated_rows=if generated {
          Some("[{\"id\":1},{\"id\":1}]")
        } else {
          None
        },
        producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"answer\":{\"fn\":\"" +
          function +
          "\"}}}},{\"select\":[\"id\",{\"value\":\"answer\"}],\"as\":\"selected\"}",
        producer_result_from="selected",
        extra_step_budget=3,
      )
      assert_true(accepted)
      assert_eq(checked.length(), 1)
    } catch {
      Source(_) | Closure(_) => {
        assert_false(accepted)
        assert_eq(checked.length(), 0)
      }
      error => raise error
    }
  }
}

///|
test "formal analytic rejects missing envelope and unbound frame aggregate obligations atomically" {
  for
    (function, limit) in [
      ("{\"fn\":\"min\",\"field\":\"value\"}", None),
      ("{\"fn\":\"sum\",\"field\":\"value\"}", Some(1000)),
      ("{\"fn\":\"array_agg\",\"field\":\"value\"}", Some(1000)),
    ] {
    let checked : Array[CheckedProgram] = []
    try {
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        second_stage=true,
        analytic_limit=limit,
        checked_results=checked,
        second_steps="[{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"current_row\",\"end\":\"current_row\"},\"functions\":{\"answer\":" +
          function +
          "}}},{\"select\":[\"id\",{\"value\":\"answer\"}],\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=3,
      )
      fail("unresolved analytic was accepted")
    } catch {
      Closure(_) => ()
      error => raise error
    }
    assert_eq(checked.length(), 0)
  }
}
