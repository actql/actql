///|
test "formal current TRAIL retains selector identity and resource scopes through imports" {
  for relation in [false, true] {
    let identity = current_trail_guarantee_identity()
    let selector = if relation {
      "{\"from\":\"starts\",\"id\":\"element\"}"
    } else {
      "{\"ids\":[" + identity + "," + identity + "]}"
    }
    let step = if relation { 4 } else { 3 }
    let suffix = ",{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"seed\",\"key\":[\"id\"]}],\"edges\":[]},\"as\":\"g\"}" +
      (if relation {
        ",{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":{\"literal\":true},\"fields\":[\"element\"]},\"as\":\"starts\"}"
      } else {
        ""
      }) +
      ",{\"from\":\"g\",\"traverse\":{\"start\":" +
      selector +
      ",\"path_mode\":\"trail\",\"emit\":\"paths\",\"min_hops\":0,\"max_hops\":1,\"direction\":\"out\"}},{\"select\":[{\"id\":\"hop_count\"},{\"value\":\"hop_count\"}],\"as\":\"projected\"}"
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      property_graph=true,
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      traversal_step=step,
      graph_output_limit=Some(1000),
      generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
      producer_expression="id",
      producer_suffix=suffix,
      producer_result_from="projected",
      extra_step_budget=if relation { 4 } else { 3 },
    ) catch {
      Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
        fail("current selector pipeline: " + @debug.to_string(issue.kind))
      Source(SourceView(Context(Stages(Capacity(stage, visit, issue))))) =>
        fail(
          "current selector capacity " +
          stage.to_string() +
          "/" +
          visit.to_string() +
          ": " +
          @debug.to_string(issue),
        )
      Source(Checks(OperationProfiles(issue))) =>
        fail("current selector profile: " + @debug.to_string(issue))
      error => raise error
    }
    let program = programs[0]
    let producer = unit_pipeline(program, 0).unwrap()
    // A separate formal SourceView program retains policy for the admitted
    // VALUES definition; an unused external Source must not lend it provenance.
    let direct = checked_direct_program_fixture(
      graph_steps="{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"seed\"},{\"filter\":\"id = id\"}" +
        suffix,
      graph_traversal="traverse",
      graph_traversal_step=step,
      graph_step_limit=if relation { 7 } else { 6 },
      property_graph=true,
    ) catch {
      Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
        fail("selector publication pipeline: " + @debug.to_string(issue.kind))
      Source(SourceView(Context(Stages(Capacity(stage, visit, issue))))) =>
        fail(
          "selector publication capacity " +
          stage.to_string() +
          "/" +
          visit.to_string() +
          ": " +
          @debug.to_string(issue),
        )
      Source(Checks(OperationProfiles(issue))) =>
        fail("selector publication profile: " + @debug.to_string(issue))
      error => raise error
    }
    let direct_unit = direct.units[0]
    let policy = publication_source_policy(direct_unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 0)
    let mut retained_traversals = 0
    for index in 0..<publication_policy_carrier_step_count(policy) {
      let retained = publication_policy_carrier_step_at(policy, index).unwrap()
      if retained.step == step {
        guard retained.operation
          is @pipeline.Traverse(selector=target, checked=operation) &&
          @pipeline.step_at(direct_unit.pipeline, step).unwrap().operation
          is @pipeline.Traverse(checked=original, ..) else {
          fail("publication lost its original TRAIL owner")
        }
        assert_true(physical_equal(operation, original))
        assert_eq(target, if relation { Some(@pipeline.Step(3)) } else { None })
        retained_traversals += 1
      }
    }
    assert_eq(retained_traversals, 1)
    let mut edges = 0
    for index in 0..<publication_policy_edge_count(policy) {
      let edge = publication_policy_edge_at(policy, index).unwrap()
      if edge.step == step {
        assert_eq(
          edge.occurrence.target,
          if edges == 0 {
            @pipeline.Step(2)
          } else {
            @pipeline.Step(3)
          },
        )
        assert_eq(
          edge.occurrence.role,
          if edges == 0 {
            @pipeline.Primary
          } else {
            @pipeline.Right
          },
        )
        edges += 1
      }
    }
    assert_eq(edges, if relation { 2 } else { 1 })
    let checks = @context.stage_requirement_operations(requirements(program))
    let counts = Array::make(5, 0)
    for i in 0..<@context.operation_closure_count(checks) {
      if @context.operation_closure_at(checks, i)
        is Some(ExecutionCheck(GraphSelectorExecution(check))) {
        assert_true(physical_equal(check.site.pipeline, producer))
        assert_eq(check.site.step, step)
        assert_eq(check.graph, @pipeline.Step(2))
        assert_eq(
          check.relation,
          if relation {
            Some(@pipeline.Step(3))
          } else {
            None
          },
        )
        assert_eq(check.site.group, 1)
        assert_eq(
          @pipeline.operation_obligations_scope(check.site.obligations),
          StartSelector,
        )
        guard check.step.operation is @pipeline.Traverse(checked=operation, ..) else {
          fail("current TRAIL owner lost")
        }
        assert_true(
          physical_equal(check.selector, @graph.traverse_start(operation)),
        )
        assert_eq(
          @graph.selector_id_count(check.selector),
          if relation {
            0
          } else {
            2
          },
        )
        let index = match check.rule {
          AdmitIdentities => 0
          RevalidateReferences => 1
          DeduplicateIdentities => 2
          RequireMembership => 3
          RequireSelectorResources => 4
        }
        counts[index] += 1
        assert_eq(
          @context.operation_execution_phase(GraphSelectorExecution(check)),
          if index == 0 || index == 1 || index == 4 {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          @context.operation_execution_failure(GraphSelectorExecution(check)),
          RejectOperationOutput,
        )
        assert_eq(
          @context.graph_selector_resource_count(check),
          if index == 4 {
            2
          } else {
            0
          },
        )
        assert_true(@context.graph_selector_resource_at(check, -1) is None)
        assert_true(@context.graph_selector_resource_at(check, 2) is None)
        if index == 4 {
          assert_eq(
            @context.graph_selector_resource_at(check, 0),
            Some(SelectorWork),
          )
          assert_eq(
            @context.graph_selector_resource_at(check, 1),
            Some(SelectorBytes),
          )
        }
      }
    }
    assert_eq(counts, if relation { [3, 3, 3, 3, 3] } else { [3, 0, 3, 3, 3] })
    assert_true(unit_publication_at(program, 1, 0) is Some(_))
  }
}
