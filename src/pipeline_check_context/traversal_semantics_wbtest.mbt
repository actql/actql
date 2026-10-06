///|
test "keyed traversal checks retain explicit mode and never reuse simple-path law obligations" {
  let producer = property_execution_pipeline()
  let graph = @pipeline.carrier_at(producer, @pipeline.Step(1)).unwrap()
  guard graph is @carrier.GraphValue(schema) else { fail("keyed Graph schema") }
  let domain = @carrier.graph_domain(@carrier.graph_definition(schema))
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  for
    (name, mode) in [
      ("walk", @graph.Walk),
      ("trail", @graph.Trail),
      ("acyclic", @graph.Acyclic),
    ] {
    let pipeline = @pipeline.check_carriers(
      asof_test_cursor(
        "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
        identity +
        "]},\"hops\":[{\"direction\":\"out\"}],\"path_mode\":\"" +
        name +
        "\",\"emit\":\"paths\"}}]",
      ),
      [("g", graph)],
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
    let step = @pipeline.step_at(pipeline, 0).unwrap()
    assert_eq(
      @pipeline.operation_profile_at(step.operation, 0),
      Some(@pipeline.Graph),
    )
    assert_eq(
      @pipeline.operation_profile_adopted_law_at(@pipeline.Graph, 0),
      Some(@pipeline.GraphLaw),
    )
    let body = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let rules : Array[TraversalRule] = []
    let mut unresolved = 0
    for index in 0..<@pipeline.operation_obligations_count(body) {
      let site : OperationRequirementSite = {
        stage: 0,
        producer_visit: 0,
        step: 0,
        group: 0,
        index,
        pipeline,
        obligations: body,
        requirement: @pipeline.operation_obligations_at(body, index).unwrap(),
      }
      match traversal_execution_check(site).unwrap() {
        Some(TraversalExecution(check)) => {
          assert_true(physical_equal(check.step, step))
          assert_eq(@graph.traverse_property_path_mode(check.operation), mode)
          assert_eq(check.input, @pipeline.Input(0))
          assert_true(check.selector_relation is None)
          rules.push(check.rule)
        }
        None => {
          assert_true(
            site.requirement
            is @pipeline.TraverseRequirement(
              ResolveTraversalResources
              | ResolveGraphTraversalProfile
            ),
          )
          unresolved += 1
        }
        _ => fail("wrong keyed traversal requirement")
      }
    }
    assert_eq(rules, [
      AdmitInputGraph,
      RespectAuthoredHops,
      FilterAuthoredLabels,
      OrderTraversalRows,
      EnumeratePropertyPaths,
      DeduplicatePathIdentities,
    ])
    assert_eq(unresolved, 2)
  }
}

///|
test "current TRAIL bindings preserve mode input roles custody and unresolved guards" {
  let producer = property_execution_pipeline()
  let graph = @pipeline.carrier_at(producer, @pipeline.Step(1)).unwrap()
  guard graph is @carrier.GraphValue(schema) else { fail("current Graph") }
  let domain = @carrier.graph_domain(@carrier.graph_definition(schema))
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[2],\"key_types\":[{\"kind\":\"number\"}]}"
  let rows = @carrier.relation(
    @carrier.rows(
      [(Qualified(Left, "element"), Some(@carrier.graph_identity(schema)))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
  )
  for
    start in [
      "{\"ids\":[" + identity + "," + identity + "]}",
      "{\"from\":\"r\",\"id\":\"left.element\"}",
    ] {
    for patterned in [false, true] {
      for emission in ["paths"] {
        let mode = if patterned {
          "\"hops\":[{\"direction\":\"out\"},{\"direction\":\"in\"}]"
        } else {
          "\"direction\":\"both\",\"min_hops\":0,\"max_hops\":9007199254740992"
        }
        let pipeline = @pipeline.check_carriers(
          asof_test_cursor(
            "[{\"from\":\"g\",\"traverse\":{\"start\":" +
            start +
            "," +
            mode +
            ",\"emit\":\"" +
            emission +
            "\",\"path_mode\":\"trail\",\"max_output_rows\":1}}]",
          ),
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
        let step = @pipeline.step_at(pipeline, 0).unwrap()
        guard step.operation is @pipeline.Traverse(checked=operation, ..) else {
          fail("traverse")
        }
        let body = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
        let expected : Array[TraversalRule] = [
          AdmitInputGraph,
          RespectAuthoredHops,
          FilterAuthoredLabels,
          OrderTraversalRows,
        ]
        expected.push(EnumeratePropertyPaths)
        expected.push(DeduplicatePathIdentities)
        let actual : Array[TraversalRule] = []
        let mut unresolved = 0
        for index in 0..<@pipeline.operation_obligations_count(body) {
          let site : OperationRequirementSite = {
            stage: 1,
            producer_visit: 2,
            step: 0,
            group: 0,
            index,
            pipeline,
            obligations: body,
            requirement: @pipeline.operation_obligations_at(body, index).unwrap(),
          }
          match traversal_execution_check(site).unwrap() {
            None => {
              assert_true(
                site.requirement
                is @pipeline.TraverseRequirement(
                  ResolveTraversalResources
                  | ResolveGraphTraversalProfile
                  | EnforceTraversalOutputGuard
                ),
              )
              unresolved += 1
            }
            Some(TraversalExecution(check)) => {
              actual.push(check.rule)
              assert_true(physical_equal(check.operation, operation))
              assert_true(physical_equal(check.step, step))
              assert_true(physical_equal(check.site, site))
              assert_eq(check.input, @pipeline.Input(0))
              assert_eq(
                check.selector_relation,
                if start.contains("from") {
                  Some(@pipeline.Input(1))
                } else {
                  None
                },
              )
              assert_eq(@graph.traverse_patterned(check.operation), patterned)
              assert_eq(
                @graph.traverse_bounds(check.operation),
                if patterned {
                  (2.0, 2.0)
                } else {
                  (0.0, 9007199254740992.0)
                },
              )
              if patterned {
                assert_eq(@graph.traverse_hop_count(check.operation), 2)
                let first = @graph.traverse_hop_at(check.operation, 0).unwrap()
                let second = @graph.traverse_hop_at(check.operation, 1).unwrap()
                assert_eq(@graph.hop_direction(first), @graph.Outgoing)
                assert_eq(@graph.hop_direction(second), @graph.Incoming)
              }
              assert_eq(
                operation_execution_phase(TraversalExecution(check)),
                if check.rule == AdmitInputGraph {
                  BeforeOperationInputUse
                } else {
                  BeforeOperationOutput
                },
              )
              assert_eq(
                operation_execution_failure(TraversalExecution(check)),
                RejectOperationOutput,
              )
              for
                changed in [
                  { ..site, step: 1, },
                  { ..site, group: 1, },
                  { ..site, index: 999, },
                ] {
                assert_true(
                  traversal_execution_check(changed)
                  is Err(ForeignOccurrence(_)),
                )
              }
            }
            _ => fail("wrong execution kind")
          }
        }
        assert_eq(actual, expected)
        assert_eq(unresolved, 3)
      }
    }
  }
}
