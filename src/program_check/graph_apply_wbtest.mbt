///|
test "formal Delta application rejects an overwritten expectation without partial success" {
  let programs : Array[CheckedProgram] = []
  try
    local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      sga=true,
      graph_construction_limit=Some(1000),
      generated_rows=Some("[]"),
      producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"},\"as\":\"g\"},{\"graph_diff\":{\"with\":\"g\"}},{\"derive\":[{\"delta\":\"1\"}],\"as\":\"changes\"},{\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"},\"from\":\"g\"},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}",
      producer_result_from="projected",
      extra_step_budget=6,
    )
  catch {
    Source(SourceView(Program(Program(Pipeline(0, issue))))) =>
      assert_eq(issue.kind, @pipeline.MissingDeltaContract)
    other => raise other
  } noraise {
    _ => fail("overwritten Delta expectation reached formal success")
  }
  assert_eq(programs.length(), 0)
}

///|
test "formal Delta application retains its independent contract and atomic checks" {
  for empty in [true, false] {
    for aliased in [true, false] {
      let programs : Array[CheckedProgram] = []
      let middle = if aliased {
        ",{\"select\":[{\"discard\":\"delta\"},{\"kept\":\"delta\"}]},{\"drop\":[\"discard\"],\"as\":\"aliased\"}"
      } else {
        ""
      }
      let field = if aliased { "kept" } else { "delta" }
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"},\"as\":\"g\"},{\"graph_diff\":{\"with\":\"g\"},\"as\":\"changes\"}" +
          middle +
          ",{\"apply_graph_delta\":{\"with\":\"" +
          (if aliased { "aliased" } else { "changes" }) +
          "\",\"field\":\"" +
          field +
          "\"},\"from\":\"g\"},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=if aliased { 7 } else { 5 },
      )
      assert_eq(programs.length(), 1)
      let program = programs[0]
      let pipeline = unit_pipeline(program, 0).unwrap()
      let ordinal = if aliased { 6 } else { 4 }
      let step = @pipeline.step_at(pipeline, ordinal).unwrap()
      guard @pipeline.step_at(pipeline, 3).unwrap().operation
        is @pipeline.GraphDiff(checked=diff, ..) else {
        fail("missing diff")
      }
      let checks = @context.stage_requirement_operations(requirements(program))
      let counts = Array::make(13, 0)
      for i in 0..<@context.operation_closure_count(checks) {
        guard @context.operation_closure_at(checks, i)
          is Some(ExecutionCheck(GraphApplyExecution(check))) else {
          continue
        }
        assert_true(physical_equal(check.site.pipeline, pipeline))
        assert_true(physical_equal(check.step, step))
        assert_eq(check.site.step, ordinal)
        assert_eq(check.base, @pipeline.Step(2))
        assert_eq(check.delta, @pipeline.Step(ordinal - 1))
        assert_eq(@graph.apply_field(check.operation), field)
        assert_true(
          physical_equal(
            @graph.apply_graph_contract(check.operation),
            @graph.diff_graph_contract(diff),
          ),
        )
        let index = match check.rule {
          RequireSingleDeltaRow => 0
          AdmitDeltaShapeAndVersion => 1
          MatchGraphContract => 2
          AdmitBaseGraph => 3
          MatchBaseIdentity => 4
          ValidateUniqueOrderedActions => 5
          MatchBeforeRecords => 6
          CheckActionExistence => 7
          ApplyChangesAtomically => 8
          AdmitResultGraph => 9
          MatchTargetIdentity => 10
          PreservePolicyDependencies => 11
          RequireApplicationResources => 12
        }
        counts[index] += 1
        assert_eq(
          @context.operation_execution_phase(GraphApplyExecution(check)),
          if index >= 8 && index <= 10 {
            BeforeOperationOutput
          } else {
            BeforeOperationInputUse
          },
        )
        assert_eq(
          @context.operation_execution_failure(GraphApplyExecution(check)),
          RejectOperationOutput,
        )
        assert_eq(
          @context.graph_apply_resource_count(check),
          if index == 12 {
            6
          } else {
            0
          },
        )
        if index == 12 {
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
              @context.graph_apply_resource_at(check, j),
              Some(resource),
            )
          }
        }
        assert_true(@context.graph_apply_resource_at(check, -1) is None)
        assert_true(@context.graph_apply_resource_at(check, 6) is None)
      }
      for n in counts {
        assert_eq(n, 3)
      }
      assert_eq(unit_count(program), 2)
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
    }
  }
}
