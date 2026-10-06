///|
// Independently SHA-256 the canonical constructor + VALUES producer preimage.
// This is an authored selector identity, not a CID copied from compiler output.
fn current_trail_guarantee_identity() -> String {
  "{\"definition\":\"N\",\"domain\":\"sha256:3c07a675d79b8ca20df7ccce6bf1282b0ac34059bfbbaec8a8cd102f5027a5c3\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
}

///|
fn current_trail_resources_suffix(
  direction : String,
  depth : String,
  guard_text? : String = "",
) -> String {
  ",{\"graph\":{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"seed\",\"key\":[\"id\"]}],\"edges\":[]},\"as\":\"g\"},{\"traverse\":{\"start\":{\"ids\":[" +
  current_trail_guarantee_identity() +
  "]},\"path_mode\":\"trail\",\"emit\":\"paths\",\"min_hops\":0,\"direction\":\"" +
  direction +
  "\",\"max_hops\":" +
  depth +
  guard_text +
  "}},{\"select\":[{\"id\":\"hop_count\"},{\"value\":\"hop_count\"}],\"as\":\"projected\"}"
}

///|
test "current TRAIL retains producer resource scopes and runtime checks through imports" {
  for direction in ["in", "out", "both"] {
    for depth in ["1", "9007199254740992"] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        graph=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=true,
        traversal_kind="traverse",
        generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
        producer_expression="id",
        producer_suffix=current_trail_resources_suffix(direction, depth),
        producer_result_from="projected",
        extra_step_budget=3,
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
      let program = programs[0]
      assert_eq(unit_traversal_limit_count(program, 0), Some(1))
      assert_eq(unit_traversal_limit_count(program, 1), Some(0))
      assert_eq(unit_traversal_limit_count(program, -1), None)
      assert_true(unit_traversal_limit_at(program, 0, -1) is None)
      assert_true(unit_traversal_limit_at(program, 0, 1) is None)
      let limit = unit_traversal_limit_at(program, 0, 0).unwrap()
      assert_eq(traversal_limit_proof_count(limit), 0)
      let selected = traversal_limit_selection(limit)
      assert_true(selected.step.operation is @pipeline.Traverse(..))
      guard selected.step.operation is @pipeline.Traverse(checked=operation, ..) &&
        @graph.traverse_input(operation) is @carrier.GraphValue(graph) else {
        fail("current TRAIL lost its typed Graph owner")
      }
      assert_eq(
        @carrier.graph_domain(@carrier.graph_definition(graph)),
        "sha256:3c07a675d79b8ca20df7ccce6bf1282b0ac34059bfbbaec8a8cd102f5027a5c3",
      )
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
        let original = @step_bounds.traversal_limit_claim(
          selected.limits,
          scope,
        )
        assert_true(@wire.limit_cid(claim) != @wire.limit_cid(original))
        assert_eq(
          @derivation.minimum_value(@wire.limit_minimum(claim)),
          @derivation.minimum_value(@wire.limit_minimum(original)),
        )
        assert_eq(
          @wire.cid(@wire.claim_at(@wire.limit_claims(claim), 0).unwrap()),
          @wire.cid(
            @wire.claim_at(
              @wire.limit_claims(original),
              @derivation.minimum_candidate_at(@wire.limit_minimum(original), 0).unwrap().node,
            ).unwrap(),
          ),
        )
      }
      let closure = @context.stage_requirement_operations(program.requirements)
      let mut resources = 0
      let mut semantics = 0
      for i in 0..<@context.operation_closure_count(closure) {
        match @context.operation_closure_at(closure, i) {
          Some(ExecutionCheck(TraversalLimits(check))) => {
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
          Some(ExecutionCheck(TraversalExecution(check))) => {
            semantics += 1
            assert_true(
              physical_equal(check.site.pipeline, selected.site.pipeline),
            )
          }
          _ => ()
        }
      }
      assert_eq((resources, semantics), (3, 18))
    }
  }
}

///|
test "current TRAIL rejects missing or differently scoped capacity without partial success" {
  for (capacity, kind) in [(false, "traverse"), (true, "shortest_path")] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        graph=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=capacity,
        traversal_kind=kind,
        generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
        producer_expression="id",
        producer_suffix=current_trail_resources_suffix("out", "1"),
        producer_result_from="projected",
        extra_step_budget=3,
      )
    catch {
      Source(
        SourceView(
          Context(
            Stages(Capacity(_, _, TraversalCollection(MissingApplication(3))))
          )
        )
      ) => assert_false(capacity)
      Source(
        SourceView(
          Context(
            Stages(Capacity(_, _, Traversal(0, SubjectMismatch(SearchPaths))))
          )
        )
      ) => assert_true(capacity)
      LocalConstructionFailure::Source(_) =>
        fail("unexpected capacity rejection boundary")
      _ => fail("capacity must fail in source preparation")
    } noraise {
      _ => fail("missing current TRAIL capacity")
    }
    assert_eq(programs.length(), 0)
  }
}

///|
test "current TRAIL cannot return a partial Program after a later imported consumer fails" {
  let programs : Array[CheckedProgram] = []
  try
    local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      graph=true,
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
      producer_expression="id",
      producer_suffix=current_trail_resources_suffix("out", "1"),
      producer_result_from="projected",
      extra_step_budget=3,
      second_steps="[{\"select\":[\"missing\"]}]",
    )
  catch {
    LocalConstructionFailure::Source(_) => ()
    _ => fail("the invalid consumer must fail source-driven preparation")
  } noraise {
    _ => fail("valid producer cannot make an invalid whole Program succeed")
  }
  assert_eq(programs.length(), 0)
}
