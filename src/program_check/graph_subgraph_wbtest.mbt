///|
test "formal subgraphs retain separate selector edges and resource scopes through imports" {
  for empty in [true, false] {
    for mode in 0..<3 {
      for edge_predicate in [true, false] {
        let selector = match mode {
          0 => "{\"ids\":[1,1]}"
          1 => "{\"where\":\"node_id > 0\"}"
          _ => "{\"from\":\"derived\",\"id\":\"id\"}"
        }
        let programs : Array[CheckedProgram] = []
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          sga=true,
          graph_construction_limit=Some(1000),
          graph_input_limit=Some(1),
          graph_output_limit=Some(1),
          generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
          producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}},{\"subgraph\":{\"nodes\":" +
            selector +
            (if edge_predicate { ",\"edges\":{\"literal\":false}" } else { "" }) +
            "}},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}",
          producer_result_from="projected",
          extra_step_budget=4,
        )
        let program = programs[0]
        let producer = unit_pipeline(program, 0).unwrap()
        let checks = @context.stage_requirement_operations(
          requirements(program),
        )
        let body_counts = Array::make(6, 0)
        let selector_counts = Array::make(6, 0)
        for i in 0..<@context.operation_closure_count(checks) {
          match @context.operation_closure_at(checks, i) {
            Some(ExecutionCheck(SubgraphExecution(check))) => {
              assert_true(physical_equal(check.site.pipeline, producer))
              assert_eq(check.site.step, 3)
              assert_eq(check.input, @pipeline.Step(2))
              assert_eq(
                check.selector_relation,
                if mode == 2 {
                  Some(@pipeline.Step(1))
                } else {
                  None
                },
              )
              assert_eq(check.site.group, 0)
              assert_eq(
                @graph.subgraph_edges(check.operation) is Some(_),
                edge_predicate,
              )
              let index = match check.rule {
                AdmitInputGraph => 0
                InduceBothEndpoints => 1
                FilterInducedEdges => 2
                PreserveIdentitiesAndProperties => 3
                PreservePolicyAndScope => 4
                RequireMaterializationResources => 5
              }
              body_counts[index] += 1
              assert_eq(
                @context.operation_execution_phase(SubgraphExecution(check)),
                if index == 0 || index == 5 {
                  BeforeOperationInputUse
                } else {
                  BeforeOperationOutput
                },
              )
              assert_eq(
                @context.operation_execution_failure(SubgraphExecution(check)),
                RejectOperationOutput,
              )
              assert_eq(
                @context.subgraph_resource_count(check),
                if index == 5 {
                  2
                } else {
                  0
                },
              )
              assert_true(@context.subgraph_resource_at(check, -1) is None)
              assert_true(@context.subgraph_resource_at(check, 2) is None)
              if index == 5 {
                assert_eq(
                  @context.subgraph_resource_at(check, 0),
                  Some(MaterializationWork),
                )
                assert_eq(
                  @context.subgraph_resource_at(check, 1),
                  Some(MaterializationBytes),
                )
              }
            }
            Some(ExecutionCheck(GraphSelectorExecution(check))) => {
              assert_true(physical_equal(check.site.pipeline, producer))
              assert_eq(check.site.step, 3)
              assert_eq(check.graph, @pipeline.Step(2))
              assert_eq(
                check.relation,
                if mode == 2 {
                  Some(@pipeline.Step(1))
                } else {
                  None
                },
              )
              assert_eq(
                @pipeline.operation_obligations_scope(check.site.obligations),
                NodeSelector,
              )
              guard check.step.operation
                is @pipeline.Subgraph(checked=operation, ..) else {
                abort("subgraph")
              }
              assert_true(
                physical_equal(check.selector, @graph.subgraph_nodes(operation)),
              )
              assert_eq(
                @graph.selector_id_count(check.selector),
                if mode == 0 {
                  2
                } else {
                  0
                },
              )
              assert_eq(
                @graph.selector_predicate(check.selector) is Some(_),
                mode == 1,
              )
              let index = match check.rule {
                AdmitIdentities => 0
                RevalidateReferences => 1
                DeduplicateIdentities => 2
                RequireMembership => 3
                EvaluateNodePredicate => 4
                RequireSelectorResources => 5
              }
              selector_counts[index] += 1
              assert_eq(
                @context.operation_execution_phase(
                  GraphSelectorExecution(check),
                ),
                if index == 0 || index == 1 || index == 5 {
                  BeforeOperationInputUse
                } else {
                  BeforeOperationOutput
                },
              )
              assert_eq(
                @context.operation_execution_failure(
                  GraphSelectorExecution(check),
                ),
                RejectOperationOutput,
              )
              assert_eq(
                @context.graph_selector_resource_count(check),
                if index == 5 {
                  2
                } else {
                  0
                },
              )
              assert_true(
                @context.graph_selector_resource_at(check, -1) is None,
              )
              assert_true(@context.graph_selector_resource_at(check, 2) is None)
              if index == 5 {
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
            _ => ()
          }
        }
        for i in 0..<6 {
          assert_eq(
            body_counts[i],
            if i == 2 && !edge_predicate {
              0
            } else {
              3
            },
          )
          assert_eq(
            selector_counts[i],
            if (i == 1 && mode != 2) || (i == 4 && mode != 1) {
              0
            } else {
              3
            },
          )
        }
        assert_true(unit_publication_at(program, 1, 0) is Some(_))
      }
    }
  }
}
