///|
test "Graph data and order bindings preserve their exact operation without closing resources" {
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    @carrier.unknown_rows(),
    @carrier.unknown_rows(),
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  for
    (body, ordered) in [
      ("{\"normalize_graph\":true}", false),
      ("{\"degree\":{\"direction\":\"both\"}}", false),
      ("{\"components\":{\"kind\":\"weak\"}}", true),
      ("{\"components\":{\"kind\":\"strong\",\"max_output_rows\":1}}", true),
      (
        "{\"graph_bounds\":{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}}",
        true,
      ),
    ] {
    let pipeline = @pipeline.check_carriers(
      asof_test_cursor("[" + body + "]"),
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
    guard step.operation is @pipeline.Graph(operation) else {
      fail("graph operation")
    }
    let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let mut data = 0
    let mut order = 0
    for index in 0..<@pipeline.operation_obligations_count(group) {
      let site : OperationRequirementSite = {
        stage: 0,
        producer_visit: 0,
        step: 0,
        group: 0,
        index,
        pipeline,
        obligations: group,
        requirement: @pipeline.operation_obligations_at(group, index).unwrap(),
      }
      match graph_execution_check(site).unwrap() {
        Some(GraphExecution(check)) => {
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.step, step))
          assert_true(physical_equal(check.operation, operation))
          assert_true(physical_equal(@graph.input(operation), graph))
          assert_eq(check.input, @pipeline.Input(0))
          let phase = match check.rule {
            AdmitGraphData => {
              data += 1
              BeforeOperationInputUse
            }
            OrderComponentIdentities => {
              assert_true(@graph.operation(operation) is Components)
              order += 1
              BeforeOperationOutput
            }
            OrderBoundsReport => {
              assert_true(@graph.operation(operation) is GraphBounds)
              order += 1
              BeforeOperationOutput
            }
          }
          assert_eq(operation_execution_phase(GraphExecution(check)), phase)
          assert_eq(
            operation_execution_failure(GraphExecution(check)),
            RejectOperationOutput,
          )
          assert_true(
            graph_execution_check({ ..site, index: 99, })
            is Err(ForeignOccurrence(0)),
          )
          assert_true(
            graph_execution_check({ ..site, step: 99, })
            is Err(ForeignOccurrence(99)),
          )
          assert_true(
            direct_execution_candidate(
              site,
              sequence_limit_policy(false),
              Ok(None),
              Ok(None),
            )
            is Ok(Some(GraphExecution(_))),
          )
        }
        None =>
          assert_true(
            site.requirement
            is @pipeline.GraphRequirement(
              ResolveSgaProfile
              | ResolveGraphResources
              | EnforceOutputGuard
            ),
          )
        _ => fail("wrong rule family")
      }
    }
    assert_eq(data, 1)
    assert_eq(order, if ordered { 1 } else { 0 })
  }
}
