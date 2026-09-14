///|
test "SourceView reach retains policy and independently selected traversal limits" {
  for direction in ["in", "out", "both"] {
    for depth in ["1", "9007199254740992"] {
      let steps = "{\"derive\":{\"value\":\"extra\"}},{\"filter\":\"id = id\"},{\"graph\":{\"source\":\"id\",\"target\":\"value\"}},{\"reach\":{\"start\":1,\"direction\":\"" +
        direction +
        "\",\"max_depth\":" +
        depth +
        "}},{\"select\":[{\"id\":\"start_id\"}]}"
      let program = checked_direct_program_fixture(
        graph_steps=steps,
        graph_traversal="reach",
      )
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(publication_policy_source_count(policy), 1)
      let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
      assert_eq(retained.step, 3)
      assert_true(retained.unknown_provenance)
      guard retained.operation is Reach(operation) else { fail("reach lost") }
      guard @pipeline.step_at(unit.pipeline, 3).unwrap().operation
        is Reach(original) else {
        fail("original reach lost")
      }
      assert_true(physical_equal(operation, original))
      assert_eq(unit_traversal_limit_count(program, 0), Some(1))
      let limit = unit_traversal_limit_at(program, 0, 0).unwrap()
      let selected = traversal_limit_selection(limit)
      assert_true(physical_equal(selected.site.pipeline, unit.pipeline))
      assert_eq(selected.site.step, 3)
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
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut limits = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(ReachLimits(check))) {
          assert_true(physical_equal(check.site.pipeline, unit.pipeline))
          assert_true(
            physical_equal(
              @step_bounds.traversal_limit_claim(check.limits, OutputRows),
              @step_bounds.traversal_limit_claim(selected.limits, OutputRows),
            ),
          )
          limits += 1
        }
      }
      assert_eq(limits, 1)
    }
  }
}
