///|
test "formal Graph diff retains typed Delta requirements across Result imports" {
  for empty in [true, false] {
    for self_diff in [true, false] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"},\"as\":\"g\"},{\"normalize_graph\":true,\"as\":\"other\"},{\"graph_diff\":{\"with\":\"" +
          (if self_diff { "other" } else { "g" }) +
          "\"}},{\"select\":[{\"id\":\"delta\"},{\"value\":\"delta\"}],\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=4,
      )
      assert_eq(programs.length(), 1)
      let program = programs[0]
      assert_eq(unit_count(program), 2)
      let producer = unit_pipeline(program, 0).unwrap()
      let step = @pipeline.step_at(producer, 4).unwrap()
      guard step.operation is @pipeline.GraphDiff(checked=operation, ..) else {
        fail("missing diff")
      }
      let checks = @context.stage_requirement_operations(requirements(program))
      let counts = Array::make(7, 0)
      for i in 0..<@context.operation_closure_count(checks) {
        guard @context.operation_closure_at(checks, i)
          is Some(ExecutionCheck(GraphDiffExecution(check))) else {
          continue
        }
        assert_true(physical_equal(check.site.pipeline, producer))
        assert_true(physical_equal(check.step, step))
        assert_true(physical_equal(check.operation, operation))
        assert_eq(check.base, @pipeline.Step(3))
        assert_eq(check.target, @pipeline.Step(if self_diff { 3 } else { 2 }))
        let index = match check.rule {
          EmitVersion => 0
          AdmitCommonSnapshots => 1
          EmitContractIdentity => 2
          BindSnapshotIdentities => 3
          EmitCompleteRecords => 4
          OrderUniqueActions => 5
          RequireDeltaResources => 6
        }
        counts[index] += 1
        assert_eq(
          @context.operation_execution_phase(GraphDiffExecution(check)),
          if index == 1 || index == 6 {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          @context.operation_execution_failure(GraphDiffExecution(check)),
          RejectOperationOutput,
        )
        assert_eq(
          @context.graph_delta_resource_count(check),
          if index == 6 {
            6
          } else {
            0
          },
        )
        if index == 6 {
          for
            j, resource in [
              @context.GraphNodes,
              GraphEdges,
              ActionRecords,
              ValueAndTemporaryBytes,
              Work,
              RetainedState,
            ] {
            assert_eq(
              @context.graph_delta_resource_at(check, j),
              Some(resource),
            )
          }
        } else {
          assert_true(@context.graph_delta_resource_at(check, 0) is None)
        }
        assert_true(@context.graph_delta_resource_at(check, -1) is None)
        assert_true(@context.graph_delta_resource_at(check, 6) is None)
      }
      for n in counts {
        assert_eq(n, 3)
      }
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
    }
  }
}
