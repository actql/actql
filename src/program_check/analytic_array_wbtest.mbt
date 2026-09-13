///|
test "formal analytic arrays select an admitted input row proof" {
  let programs : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    generated_proofs=[keyed_sourceview_claim()],
    second_stage=true,
    through_check=true,
    analytic_limit=Some(1000),
    checked_results=programs,
    second_steps="[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"value\",\"max_items\":2}}}},{\"select\":[\"id\",{\"value\":\"items\"}],\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=6,
  )
  let closure = @context.stage_requirement_operations(requirements(programs[0]))
  let mut found = false
  for i in 0..<@context.operation_closure_count(closure) {
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(AnalyticExecution(check))) &&
      check.rule is EnforceArrayItems(_, limit) else {
      continue
    }
    found = true
    assert_eq(check.site.stage, 1)
    assert_eq(check.site.step, 2)
    assert_eq(@context.group_array_limit_maximum(limit), 1L)
    assert_true(@context.group_array_limit_candidate_count(limit) > 0)
    assert_eq(
      @context.group_array_limit_input_law(limit),
      "actql.bound.analytic-array-input",
    )
  }
  assert_true(found)
}

///|
test "formal analytic arrays bind host and author guards per frame through imports" {
  for rows in ["[]", "[{\"id\":1},{\"id\":1}]"] {
    for
      guard_text in [
        "", ",\"max_items\":1", ",\"max_items\":{\"$param\":\"n\"}",
      ] {
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        second_stage=true,
        parameters=true,
        analytic_limit=Some(1000),
        generated_rows=Some(rows),
        checked_results=checked,
        producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"items\":{\"fn\":\"array_agg\",\"field\":\"value\"" +
          guard_text +
          "}}}},{\"select\":[\"id\",{\"value\":\"items\"}],\"as\":\"selected\"}",
        producer_result_from="selected",
        extra_step_budget=4,
      )
      assert_eq(checked.length(), 1)
      let program = checked[0]
      let source = unit_analytic_aggregate_source_at(program, 0, 2, 0).unwrap()
      assert_eq(source.scope, "items")
      assert_eq(
        analytic_aggregate_subject(source, 1000),
        "unit:" +
        unit_definition_cid(program, 0).unwrap() +
        "#/steps/2/analytic/functions/items/items",
      )
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut links = 0
      let mut imported = 0
      for i in 0..<@context.operation_closure_count(closure) {
        guard @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(AnalyticExecution(check))) &&
          check.rule is EnforceArrayItems(call, limit) else {
          continue
        }
        links += 1
        if check.site.stage != 0 {
          imported += 1
        }
        assert_true(
          physical_equal(
            check.site.pipeline,
            unit_pipeline(program, 0).unwrap(),
          ),
        )
        assert_eq(check.site.step, 2)
        assert_eq(check.input, @pipeline.Step(1))
        assert_true(physical_equal(call, source.call))
        guard call.function is @relation.Aggregate(aggregate) else {
          fail("not array aggregate")
        }
        assert_true(
          physical_equal(@context.group_array_limit_call(limit), aggregate),
        )
        assert_eq(
          @context.group_array_limit_input_law(limit),
          "actql.bound.analytic-array-input",
        )
        assert_eq(
          @context.group_array_limit_maximum(limit),
          if guard_text == "" {
            1000L
          } else {
            1L
          },
        )
        // No Program proofs were supplied. Source literals do not fabricate
        // an admitted capacity claim or replace the selected Host ceiling.
        assert_eq(@context.group_array_limit_candidate_count(limit), 0)
        assert_eq(
          @context.group_array_limit_guard_resolution(limit) is Some(_),
          guard_text.contains("$param"),
        )
        if @context.group_array_limit_guard_resolution(limit) is Some(bound) {
          assert_true(physical_equal(bound.site.pipeline, check.site.pipeline))
          assert_eq(bound.site.producer_visit, check.site.producer_visit)
          assert_eq(bound.site.step, check.site.step)
        }
        if links == 1 {
          let owner = @context.group_array_limit_owner(limit)
          let req = @context.group_array_limit_requirement(limit)
          assert_true(
            @context.select_group_array_limit(owner, req, 100000000, 1000)
            is Err(InvalidRequirement),
          )
          let linked = @context.link_program_analytic_array_limits(
            owner, 100000000, 1000, 1000,
          ).unwrap()
          let work = @context.operation_resolution_work(linked)
          assert_true(
            @context.link_program_analytic_array_limits(owner, work, 1000, 1000)
            is Ok(_),
          )
          assert_true(
            @context.link_program_analytic_array_limits(
              owner,
              work - 1,
              1000,
              1000,
            )
            is Err(BudgetExceeded),
          )
          assert_true(
            @context.link_program_analytic_array_limits(owner, work, 0, 1000)
            is Err(BudgetExceeded),
          )
          assert_true(
            @context.link_program_analytic_array_limits(owner, work, 1000, 0)
            is Err(BudgetExceeded),
          )
        }
      }
      assert_true(links > 1)
      assert_true(imported > 0)
    }
  }
}
