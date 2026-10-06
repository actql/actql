///|
fn current_match_custody_graph() -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @carrier.graph_node_definition(
    "N",
    [@contract.primitive(NumberType, nullable=false)],
    empty,
    [],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let edge = @carrier.graph_edge_definition(
    @carrier.graph_node_definition(
      "E",
      [@contract.primitive(NumberType, nullable=false)],
      empty,
      [],
      max_fields=1,
      max_name_bytes=1,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  @carrier.graph(
    "sha256:" + "1".repeat(64),
    [node],
    [edge],
    max_definitions=2,
    max_contract_work=100,
  ).unwrap()
}

///|
fn current_match_custody_pipeline(
  graph : @carrier.Carrier,
  entity : String,
) -> @pipeline.CheckedPipeline {
  let definition = if entity == "nodes" { "N" } else { "E" }
  @pipeline.check_carriers(
    asof_test_cursor(
      "[{\"match_" +
      entity +
      "\":{\"definition\":\"" +
      definition +
      "\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}]",
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
}

///|
test "keyed MATCH retains validation ordering capacity and exact checked owners" {
  for entity in ["nodes", "edges"] {
    let graph = current_match_custody_graph()
    let pipeline = current_match_custody_pipeline(graph, entity)
    let foreign = current_match_custody_pipeline(graph, entity)
    let step = @pipeline.step_at(pipeline, 0).unwrap()
    guard step.operation is @pipeline.GraphMatch(operation) else {
      fail("MATCH")
    }
    let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let foreign_obligations = @pipeline.operation_obligation_group_at(
      @pipeline.step_at(foreign, 0).unwrap().operation,
      0,
    ).unwrap()
    let expected : Array[GraphMatchRule?] = [
      Some(AdmitGraph),
      Some(OrderMatches),
      Some(EnforceMatchResources),
      None,
      Some(EvaluatePredicate),
    ]
    assert_eq(
      @pipeline.operation_obligations_count(obligations),
      expected.length(),
    )
    let policy = sequence_limit_policy(false)
    let mut linked = 0
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
      match (graph_match_execution_check(site, policy).unwrap(), rule) {
        (Some(GraphMatchExecution(check)), Some(rule)) => {
          linked += 1
          assert_eq(check.rule, rule)
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.step, step))
          assert_true(physical_equal(check.operation, operation))
          assert_true(
            physical_equal(@graph.match_input(check.operation), graph),
          )
          assert_true(physical_equal(check.policy, policy))
          assert_eq(check.input, @pipeline.Input(0))
          assert_true(
            physical_equal(@policy.ceiling_policy(check.output_rows), policy),
          )
          assert_eq(
            @policy.ceiling_field(check.output_rows),
            "max_relation_output_rows",
          )
          assert_eq(
            operation_execution_phase(GraphMatchExecution(check)),
            if rule == AdmitGraph || rule == EnforceMatchResources {
              BeforeOperationInputUse
            } else {
              BeforeOperationOutput
            },
          )
          assert_eq(
            operation_execution_failure(GraphMatchExecution(check)),
            RejectOperationOutput,
          )
          assert_eq(
            graph_match_resource_count(check),
            if rule == EnforceMatchResources {
              3
            } else {
              0
            },
          )
          assert_true(
            direct_execution_candidate(site, policy, Ok(None), Ok(None))
            is Ok(Some(GraphMatchExecution(_))),
          )
          for
            bad in [
              { ..site, index: 99, },
              { ..site, step: 99, },
              { ..site, group: 1, },
              { ..site, pipeline: foreign, },
              { ..site, obligations: foreign_obligations, },
            ] {
            assert_true(
              graph_match_execution_check(bad, policy)
              is Err(ForeignOccurrence(_)),
            )
          }
          let other_policy = sequence_limit_policy(false)
          guard graph_match_execution_check(site, other_policy)
            is Ok(Some(GraphMatchExecution(other))) else {
            fail("missing distinct policy")
          }
          assert_false(physical_equal(check.policy, other.policy))
          assert_true(
            physical_equal(
              @policy.ceiling_policy(other.output_rows),
              other_policy,
            ),
          )
        }
        (None, None) => assert_eq(index, 3)
        _ => fail("wrong MATCH execution rule")
      }
    }
    assert_eq(linked, 4)
  }
}
