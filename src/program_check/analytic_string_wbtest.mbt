///|
test "formal analytic string bounds select Host and authored limits per frame and retain imported ownership" {
  for host in [None, Some(4), Some(8)] {
    for
      guard_text in [
        "", ",\"max_bytes\":2", ",\"max_bytes\":{\"$param\":\"n\"}",
      ] {
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        second_stage=true,
        parameters=true,
        analytic_limit=Some(1000),
        string_limit=host,
        checked_results=checked,
        producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"text\":{\"fn\":\"string_agg\",\"expr\":\"to_string(value)\",\"delimiter\":\"é\"" +
          guard_text +
          "}}}},{\"select\":[\"id\",{\"value\":\"text\"}],\"as\":\"selected\"}",
        producer_result_from="selected",
        extra_step_budget=3,
      )
      assert_eq(checked.length(), 1)
      let program = checked[0]
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut links = 0
      let mut imported = 0
      let mut contracts = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(AnalyticExecution(check))) &&
          check.rule is ValidateResultContract(call) {
          assert_true(host is None && guard_text == "")
          assert_eq(call.name, "text")
          assert_true(
            physical_equal(
              check.site.pipeline,
              unit_pipeline(program, 0).unwrap(),
            ),
          )
          contracts += 1
        }
        guard @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(AnalyticExecution(check))) &&
          check.rule is EnforceStringBytes(call, limit) else {
          continue
        }
        links += 1
        if links == 1 {
          let owner = @context.group_string_limit_owner(limit)
          let req = @context.group_string_limit_requirement(limit)
          assert_true(
            @context.select_group_string_limit(owner, req, 10000000, 1000)
            is Err(InvalidRequirement),
          )
          let linked = @context.link_program_analytic_string_limits(
            owner, 10000000, 1000, 1000,
          ).unwrap()
          let work = @context.operation_resolution_work(linked)
          assert_true(
            @context.link_program_analytic_string_limits(
              owner, work, 1000, 1000,
            )
            is Ok(_),
          )
          assert_true(
            @context.link_program_analytic_string_limits(
              owner,
              work - 1,
              1000,
              1000,
            )
            is Err(BudgetExceeded),
          )
          assert_true(
            @context.link_program_analytic_string_limits(owner, work, 0, 1000)
            is Err(BudgetExceeded),
          )
          assert_true(
            @context.link_program_analytic_string_limits(owner, work, 1000, 0)
            is Err(BudgetExceeded),
          )
        }
        if check.site.stage != 0 {
          imported += 1
        }
        assert_true(
          physical_equal(
            check.site.pipeline,
            unit_pipeline(program, 0).unwrap(),
          ),
        )
        assert_eq(check.site.step, 1)
        assert_eq(call.name, "text")
        assert_true(call.result.nullable)
        assert_true(call.result.shape is @contract.Text(_))
        guard call.function is @relation.Aggregate(aggregate) else {
          fail("not aggregate")
        }
        assert_true(
          physical_equal(@context.group_string_limit_call(limit), aggregate),
        )
        let expected = if guard_text == "" {
          host.unwrap().to_int64()
        } else if guard_text.contains("$param") {
          1L
        } else {
          2L
        }
        assert_eq(@context.group_string_limit_maximum(limit), expected)
        assert_eq(
          @context.group_string_limit_host(limit) is Some(_),
          host is Some(_),
        )
        assert_eq(
          @context.group_string_limit_guard_resolution(limit) is Some(_),
          guard_text.contains("$param"),
        )
        if @context.group_string_limit_guard_resolution(limit)
          is Some(resolution) {
          assert_true(
            physical_equal(resolution.site.pipeline, check.site.pipeline),
          )
          assert_eq(resolution.site.producer_visit, check.site.producer_visit)
          assert_eq(resolution.site.step, check.site.step)
        }
      }
      if host is None && guard_text == "" {
        assert_eq(links, 0)
        assert_true(contracts > 1)
      } else {
        assert_true(links > 1)
        assert_true(imported > 0)
      }
    }
  }
}
