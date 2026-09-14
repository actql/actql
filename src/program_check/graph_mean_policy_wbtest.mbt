///|
test "Graph mean policy retains zero-weight sources and ordered sample ownership" {
  for separate in [false, true] {
    for missing in ["exclude", "zero"] {
      for nulls in ["exclude", "zero", "fail"] {
        let graph = fn(source, name) {
          "{\"graph\":{\"nodes\":{\"from\":\"" +
          source +
          "\",\"id\":\"id\",\"fields\":[\"extra\"]},\"edges\":{\"from\":\"" +
          source +
          "\",\"source\":\"id\",\"target\":\"id\",\"fields\":[]}},\"as\":\"" +
          name +
          "\"}"
        }
        let steps = graph("remote", "g") +
          "," +
          graph(if separate { "right" } else { "remote" }, "h") +
          ",{\"mean_graphs\":{\"with\":[\"g\",\"h\",\"h\"],\"weights\":[0,1,2],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{\"extra\":{\"mean\":{\"missing\":\"" +
          missing +
          "\",\"nulls\":\"" +
          nulls +
          "\"}}},\"edges\":{}}},\"as\":\"mean\"},{\"node_rows\":true}"
        let program = checked_direct_program_fixture(
          graph_steps=steps,
          graph_right=separate,
        )
        let unit = program.units[0]
        let policy = publication_source_policy(unit.publications[0]).unwrap()
        assert_eq(
          publication_policy_source_count(policy),
          if separate {
            2
          } else {
            1
          },
        )
        let retained = publication_policy_carrier_step_at(policy, 1).unwrap()
        assert_eq(retained.step, 2)
        assert_true(retained.unknown_provenance)
        guard retained.operation is GraphMean(operation) else {
          fail("mean lost")
        }
        let step = @pipeline.step_at(unit.pipeline, 2).unwrap()
        guard step.operation is GraphMean(original) else {
          fail("original mean lost")
        }
        assert_true(physical_equal(operation, original))
        assert_true(step.input is None)
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut resources = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(GraphMeanExecution(check))) {
            assert_true(physical_equal(check.step, step))
            assert_eq(@context.graph_mean_sample_count(check), 3)
            for sample in 0..<3 {
              let (input, weight) = @context.graph_mean_sample_at(check, sample).unwrap()
              assert_eq(input.role, @pipeline.Sample(sample))
              assert_eq(
                input.target,
                @pipeline.Step(if sample == 0 { 0 } else { 1 }),
              )
              assert_eq(weight, sample.to_double())
            }
            if check.rule == RequireMeanResources {
              resources += 1
              assert_eq(@context.graph_mean_resource_count(check), 4)
            }
          }
        }
        assert_eq(resources, 1)
      }
    }
  }
}
