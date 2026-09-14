///|
test "selector bindings retain endpoint roles and reject foreign checked owners" {
  let fields = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  let graph = @carrier.graph(
    number,
    fields,
    fields,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let rows = @carrier.relation(
    @carrier.rows(
      [(Unqualified("id"), Some(number))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=10,
    ).unwrap(),
  )
  let policy = sequence_limit_policy(false)
  for
    body in [
      "{\"subgraph\":{\"nodes\":{\"ids\":[1,1]}}}", "{\"subgraph\":{\"nodes\":{\"from\":\"r\",\"id\":\"id\"}}}",
      "{\"traverse\":{\"start\":{\"from\":\"r\",\"id\":\"id\"},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"nodes\"}}",
      "{\"shortest_path\":{\"source\":{\"from\":\"r\",\"id\":\"id\"},\"target\":2,\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
      "{\"shortest_path\":{\"source\":1,\"target\":{\"from\":\"r\",\"id\":\"id\"},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
      "{\"shortest_path\":{\"source\":{\"from\":\"r\",\"id\":\"id\"},\"target\":{\"from\":\"r\",\"id\":\"id\"},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2}}",
    ] {
    let build = fn() {
      @pipeline.check_carriers(
        asof_test_cursor("[{\"from\":\"g\"," + body[1:].to_owned() + "]"),
        [("g", graph), ("r", rows)],
        None,
        None,
        {
          max_steps: 1,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 10000,
          max_tokens: 10000,
          max_depth: 100,
        },
      ).unwrap()
    }
    let pipeline = build()
    let foreign = build()
    let step = @pipeline.step_at(pipeline, 0).unwrap()
    let foreign_step = @pipeline.step_at(foreign, 0).unwrap()
    for
      group_index in 1..<@pipeline.operation_obligation_group_count(
        step.operation,
      ) {
      let group = @pipeline.operation_obligation_group_at(
        step.operation,
        group_index,
      ).unwrap()
      for index in 0..<@pipeline.operation_obligations_count(group) {
        let site : OperationRequirementSite = {
          stage: 0,
          producer_visit: 0,
          step: 0,
          group: group_index,
          index,
          pipeline,
          obligations: group,
          requirement: @pipeline.operation_obligations_at(group, index).unwrap(),
        }
        guard graph_selector_execution_check(site, policy)
          is Ok(Some(GraphSelectorExecution(check))) else {
          fail("missing selector check")
        }
        assert_true(physical_equal(check.site, site))
        assert_true(physical_equal(check.step, step))
        assert_true(physical_equal(check.policy, policy))
        assert_eq(check.graph, @pipeline.Input(0))
        assert_eq(
          check.relation,
          if @graph.selector_form(check.selector) is RelationIds(..) {
            Some(@pipeline.Input(1))
          } else {
            None
          },
        )
        assert_true(
          graph_selector_execution_check({ ..site, step: 1, }, policy)
          is Err(ForeignOccurrence(1)),
        )
        assert_true(
          graph_selector_execution_check({ ..site, group: 0, }, policy)
          is Err(ForeignOccurrence(0)),
        )
        assert_true(
          graph_selector_execution_check({ ..site, index: 99, }, policy)
          is Err(ForeignOccurrence(0)),
        )
        assert_true(
          graph_selector_execution_check({ ..site, pipeline: foreign, }, policy)
          is Err(ForeignOccurrence(0)),
        )
        let foreign_group = @pipeline.operation_obligation_group_at(
          foreign_step.operation,
          group_index,
        ).unwrap()
        assert_true(
          graph_selector_execution_check(
            { ..site, obligations: foreign_group, },
            policy,
          )
          is Err(ForeignOccurrence(0)),
        )
        if @pipeline.operation_obligation_group_count(step.operation) == 3 {
          let other = @pipeline.operation_obligation_group_at(
            step.operation,
            if group_index == 1 {
              2
            } else {
              1
            },
          ).unwrap()
          assert_true(
            graph_selector_execution_check(
              { ..site, obligations: other, },
              policy,
            )
            is Err(ForeignOccurrence(0)),
          )
        }
      }
    }
    if step.operation is Subgraph(..) {
      let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
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
        if site.requirement is SubgraphRequirement(ResolveSubgraphProfile) {
          assert_true(subgraph_execution_check(site, policy) is Ok(None))
        } else {
          assert_true(
            subgraph_execution_check(site, policy)
            is Ok(Some(SubgraphExecution(_))),
          )
          assert_true(
            subgraph_execution_check({ ..site, group: 1, }, policy)
            is Err(ForeignOccurrence(0)),
          )
          assert_true(
            subgraph_execution_check({ ..site, index: 99, }, policy)
            is Err(ForeignOccurrence(0)),
          )
        }
      }
    }
  }
}
