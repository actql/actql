///|
test "current TRAIL retains original publication and independently selected traversal limit owners" {
  for direction in ["in", "out", "both"] {
    for depth in ["1", "9007199254740992"] {
      // An admitted Values producer owns this definition. The unused Source
      // cannot lend provenance to it; external Source-definition admission
      // requires separate admission, not inference from its name or bound bytes.
      let steps = "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"seed\"},{\"filter\":\"id = id\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"seed\",\"key\":[\"id\"]}],\"edges\":[]},\"as\":\"g\"},{\"traverse\":{\"start\":{\"ids\":[" +
        current_trail_guarantee_identity() +
        "]},\"path_mode\":\"trail\",\"emit\":\"paths\",\"min_hops\":0,\"direction\":\"" +
        direction +
        "\",\"max_hops\":" +
        depth +
        "}},{\"select\":[{\"id\":\"hop_count\"}]}"
      let program = checked_direct_program_fixture(
        graph_steps=steps,
        graph_traversal="traverse",
        property_graph=true,
      ) catch {
        Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
          fail("current TRAIL pipeline: " + @debug.to_string(issue.kind))
        Source(SourceView(Context(Stages(Capacity(stage, visit, issue))))) =>
          fail(
            "current TRAIL capacity " +
            stage.to_string() +
            "/" +
            visit.to_string() +
            ": " +
            @debug.to_string(issue),
          )
        Source(Checks(OperationProfiles(issue))) =>
          fail("current TRAIL profile: " + @debug.to_string(issue))
        error => raise error
      }
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(publication_policy_source_count(policy), 0)
      let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
      assert_eq(retained.step, 3)
      assert_true(retained.unknown_provenance)
      guard retained.operation is Traverse(checked=operation, ..) else {
        fail("current TRAIL lost")
      }
      guard @pipeline.step_at(unit.pipeline, 3).unwrap().operation
        is Traverse(checked=original, ..) else {
        fail("original current TRAIL lost")
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
          "#/steps/3/traverse/" +
          suffix,
        )
        assert_eq(@derivation.minimum_value(@wire.limit_minimum(claim)), 1000L)
      }
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut limits = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(TraversalLimits(check))) {
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
