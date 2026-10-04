///|
test "subgraph execution binds each body obligation to its checked owner" {
  let graph = current_match_custody_graph()
  guard graph is @carrier.GraphValue(value) else { fail("Graph") }
  let domain = @carrier.property_graph_domain(
    @carrier.graph_property_definition(value),
  )
  let pipeline = @pipeline.check_carriers(
    asof_test_cursor(
      "[{\"from\":\"g\",\"subgraph\":{\"nodes\":{\"ids\":[{\"definition\":\"N\",\"domain\":\"" +
        domain +
        "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}]}}}]",
    ),
    [("g", graph)],
    None,
    None,
    {
      max_steps: 1,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let step = @pipeline.step_at(pipeline, 0).unwrap()
  guard step.operation is @pipeline.Subgraph(checked=operation, ..) else {
    fail("subgraph")
  }
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  let expected : Array[SubgraphExecutionRule?] = [
    Some(AdmitSubgraphGraph),
    Some(InduceSubgraphEndpoints),
    Some(PreserveSubgraphIdentities),
    Some(PreserveSubgraphPolicy),
    Some(EnforceSubgraphResources),
    None,
  ]
  assert_eq(@pipeline.operation_obligations_count(obligations), expected.length())
  let policy = property_execution_policy()
  for index, rule in expected {
    let site : OperationRequirementSite = {
      stage: 0,
      producer_visit: 0,
      step: 0,
      group: 0,
      index,
      pipeline,
      obligations,
      requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
    }
    match (subgraph_execution_check(site, policy).unwrap(), rule) {
      (Some(SubgraphExecution(check)), Some(rule)) => {
        assert_eq(check.rule, rule)
        assert_true(physical_equal(check.site, site))
        assert_true(physical_equal(check.step, step))
        assert_true(physical_equal(check.operation, operation))
        assert_eq(check.graph, @pipeline.Input(0))
        assert_true(check.relation is None)
        assert_true(physical_equal(check.policy, policy))
        assert_eq(
          @policy.ceiling_field(check.output_nodes),
          "max_graph_construction_nodes",
        )
        assert_eq(
          @policy.ceiling_field(check.output_edges),
          "max_graph_construction_edges",
        )
        assert_eq(
          operation_execution_phase(SubgraphExecution(check)),
          if rule == AdmitSubgraphGraph || rule == EnforceSubgraphResources {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          operation_execution_failure(SubgraphExecution(check)),
          RejectOperationOutput,
        )
        assert_true(
          direct_execution_candidate(site, policy, Ok(None), Ok(None))
          is Ok(Some(SubgraphExecution(_))),
        )
        for bad in [
          { ..site, index: 99, },
          { ..site, step: 99, },
          { ..site, group: 1, },
        ] {
          assert_true(
            subgraph_execution_check(bad, policy) is Err(ForeignOccurrence(_)),
          )
        }
      }
      (None, None) => assert_eq(index, 5)
      _ => fail("wrong subgraph execution rule at " + index.to_string())
    }
  }
}
