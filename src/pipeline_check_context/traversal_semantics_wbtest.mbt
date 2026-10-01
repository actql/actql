///|
test "keyed traversal checks retain explicit mode and never reuse simple-path law obligations" {
  let producer = property_execution_pipeline()
  let graph = @pipeline.carrier_at(producer, @pipeline.Step(1)).unwrap()
  guard graph is @carrier.GraphValue(schema) else { fail("keyed Graph schema") }
  let domain = @carrier.property_graph_domain(
    @carrier.graph_property_definition(schema).unwrap(),
  )
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
      Some(@pipeline.PropertyGraph),
    )
    assert_eq(
      @pipeline.operation_profile_adopted_law_at(@pipeline.PropertyGraph, 0),
      Some(@pipeline.PropertyGraphLaw),
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
          assert_eq(
            @graph.traverse_property_path_mode(check.operation),
            Some(mode),
          )
          assert_eq(check.input, @pipeline.Input(0))
          assert_true(check.selector_relation is None)
          rules.push(check.rule)
        }
        None => {
          assert_true(
            site.requirement
            is @pipeline.TraverseRequirement(
              ResolveTraversalResources
              | ResolvePropertyGraphTraversalProfile
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
      EvaluateHopConditions,
      OrderTraversalRows,
      EnumeratePropertyPaths,
      DeduplicatePathIdentities,
    ])
    assert_eq(unresolved, 2)
  }
}

///|
test "traversal semantic bindings preserve mode predicates input roles and unresolved guards" {
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
  for
    start in [
      "{\"ids\":[2,2]}", "{\"from\":\"r\",\"id\":\"id\"}", "{\"where\":{\"literal\":false}}",
    ] {
    for patterned in [false, true] {
      for emission in ["nodes", "paths"] {
        let mode = if patterned {
          "\"hops\":[{\"direction\":\"out\",\"edge_where\":{\"literal\":false}},{\"direction\":\"in\",\"node_where\":{\"literal\":true}}]"
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
            "\",\"max_output_rows\":1}}]",
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
          EvaluateHopConditions,
          OrderTraversalRows,
        ]
        if emission == "nodes" {
          expected.push(EmitMinimumDepth)
        } else {
          expected.push(EnumerateSimplePaths)
          expected.push(DeduplicatePathIdentities)
        }
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
                  | ResolveTraversalProfile
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
                assert_true(
                  @graph.hop_predicate(first, @graph.Edges) is Some(_),
                )
                assert_true(
                  @graph.hop_predicate(second, @graph.Nodes) is Some(_),
                )
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
