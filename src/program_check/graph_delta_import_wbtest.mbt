///|
test "formal Delta imports carry producer contracts into consumer application" {
  for empty in [true, false] {
    for overwritten in [false, true] {
      let programs : Array[CheckedProgram] = []
      let rows = if empty { "[]" } else { "[{\"id\":1}]" }
      let prefix = if overwritten {
        "{\"derive\":[{\"id\":\"1\"}],\"from\":\"rows\",\"as\":\"changed\"},"
      } else {
        ""
      }
      try
        local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          sga=true,
          graph_construction_limit=Some(1000),
          generated_rows=Some(rows),
          producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"},\"as\":\"g\"},{\"graph_diff\":{\"with\":\"g\"}},{\"select\":[{\"id\":\"delta\"},{\"value\":\"delta\"}],\"as\":\"projected\"}",
          producer_result_from="projected",
          extra_step_budget=9,
          second_steps="[" +
            prefix +
            "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
            rows +
            "},\"as\":\"seed\"},{\"derive\":{\"value\":\"id + 1\"}},{\"graph\":{\"source\":\"id\",\"target\":\"value\"},\"as\":\"base\"},{\"apply_graph_delta\":{\"with\":\"" +
            (if overwritten { "changed" } else { "rows" }) +
            "\",\"field\":\"id\"}},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"restored\"}]",
          second_result_from="restored",
        )
      catch {
        Source(SourceView(Program(Program(Pipeline(1, issue))))) => {
          assert_true(overwritten)
          assert_eq(issue.kind, @pipeline.MissingDeltaContract)
        }
        other => raise other
      } noraise {
        _ => assert_false(overwritten)
      }
      assert_eq(programs.length(), if overwritten { 0 } else { 1 })
      if overwritten {
        continue
      }
      let program = programs[0]
      let producer = unit_pipeline(program, 0).unwrap()
      let consumer = unit_pipeline(program, 1).unwrap()
      guard @pipeline.step_at(producer, 3).unwrap().operation
        is @pipeline.GraphDiff(checked=diff, ..) else {
        fail("missing producer diff")
      }
      let expected = @graph.diff_graph_contract(diff)
      let operations = @context.stage_requirement_operations(
        requirements(program),
      )
      let mut applications = 0
      for i in 0..<@context.operation_closure_count(operations) {
        guard @context.operation_closure_at(operations, i)
          is Some(ExecutionCheck(GraphApplyExecution(check))) else {
          continue
        }
        applications += 1
        assert_eq(check.site.stage, 1)
        assert_eq(check.site.step, 3)
        assert_true(physical_equal(check.site.pipeline, consumer))
        assert_eq(check.base, @pipeline.Step(2))
        guard check.delta is @pipeline.Input(index) else {
          fail("Delta must be an import")
        }
        assert_eq(@pipeline.input_at(consumer, index).unwrap().0, "rows")
        assert_true(
          physical_equal(@graph.apply_graph_contract(check.operation), expected),
        )
        assert_true(
          physical_equal(
            @pipeline.expected_delta_contract(
              consumer,
              Input(index),
              Unqualified("id"),
            ).unwrap(),
            expected,
          ),
        )
        assert_true(
          physical_equal(
            @pipeline.producer_pipeline(
              @pipeline.input_producer(consumer, index).unwrap(),
            ),
            producer,
          ),
        )
      }
      assert_eq(applications, 13)
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
      assert_true(
        unit_definition_cid(program, 0) != unit_definition_cid(program, 1),
      )
    }
  }
}
