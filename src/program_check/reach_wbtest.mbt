///|
fn reach_program_suffix(direction : String, depth : String) -> String {
  ",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"reach\":{\"start\":1,\"direction\":\"" +
  direction +
  "\",\"max_depth\":" +
  depth +
  "}},{\"select\":[{\"id\":\"start_id\"},{\"value\":\"depth\"}],\"as\":\"projected\"}"
}

///|
test "formal reach retains producer resource scopes expansion and runtime checks through imports" {
  for direction in ["in", "out", "both"] {
    for depth in ["1", "9007199254740992"] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=true,
        traversal_kind="reach",
        generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
        producer_expression="id",
        producer_suffix=reach_program_suffix(direction, depth),
        producer_result_from="projected",
        extra_step_budget=3,
      )
      let program = programs[0]
      assert_eq(unit_traversal_limit_count(program, 0), Some(1))
      assert_eq(unit_traversal_limit_count(program, 1), Some(0))
      let limit = unit_traversal_limit_at(program, 0, 0).unwrap()
      let selected = traversal_limit_selection(limit)
      assert_true(selected.step.operation is @pipeline.Reach(_))
      for
        (scope, suffix) in [
          (@step_bounds.SearchPaths, "paths"),
          (@step_bounds.OutputRows, "output"),
        ] {
        let claim = traversal_limit_claim(limit, scope)
        assert_eq(
          @wire.limit_subject(claim),
          "unit:" +
          unit_definition_cid(program, 0).unwrap() +
          "#/steps/3/reach/" +
          suffix,
        )
        assert_eq(@derivation.minimum_value(@wire.limit_minimum(claim)), 1000L)
      }
      let closure = @context.stage_requirement_operations(program.requirements)
      let mut resources = 0
      let mut semantics = 0
      for i in 0..<@context.operation_closure_count(closure) {
        match @context.operation_closure_at(closure, i) {
          Some(ExecutionCheck(ReachLimits(check))) => {
            resources += 1
            assert_true(
              physical_equal(check.site.pipeline, selected.site.pipeline),
            )
            assert_true(
              physical_equal(
                @step_bounds.traversal_limit_claim(check.limits, OutputRows),
                @step_bounds.traversal_limit_claim(selected.limits, OutputRows),
              ),
            )
          }
          Some(ExecutionCheck(ReachExecution(check))) => {
            semantics += 1
            assert_true(
              physical_equal(check.site.pipeline, selected.site.pipeline),
            )
          }
          _ => ()
        }
      }
      assert_eq((resources, semantics), (3, 12))
    }
  }
}

///|
test "formal reach rejects missing or differently scoped capacity without partial success" {
  for (capacity, kind) in [(false, "reach"), (true, "traverse")] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=capacity,
        traversal_kind=kind,
        generated_rows=Some("[]"),
        producer_expression="id",
        producer_suffix=reach_program_suffix("out", "1"),
        producer_result_from="projected",
        extra_step_budget=3,
      )
    catch {
      LocalConstructionFailure::Source(_) => ()
      _ => fail("capacity must fail in source preparation")
    } noraise {
      _ => fail("missing reach capacity")
    }
    assert_eq(programs.length(), 0)
  }
}
