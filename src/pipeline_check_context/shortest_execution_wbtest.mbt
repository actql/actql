///|
test "shortest checks retain both endpoint roles weights selection and unresolved capacity" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nodes = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let edges = @carrier.rows(
    [(Unqualified("cost"), Some(number))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let graph = @carrier.graph(
    number,
    nodes,
    edges,
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
    (source, target, left, right, sets) in [
      ("1", "1", false, false, false),
      ("{\"from\":\"r\",\"id\":\"id\"}", "2", true, false, true),
      ("1", "{\"from\":\"r\",\"id\":\"id\"}", false, true, true),
      (
        "{\"from\":\"r\",\"id\":\"id\"}", "{\"from\":\"r\",\"id\":\"id\"}", true,
        true, true,
      ),
      ("{\"ids\":[1,1]}", "{\"where\":{\"literal\":false}}", false, false, true),
    ] {
    for
      (selection, expected) in [
        ("each_pair", @graph.EachPair),
        ("nearest_pair", @graph.NearestPair),
        ("nearest_per_source", @graph.NearestPerSource),
      ] {
      if !sets && selection != "each_pair" {
        continue
      }
      for weighted in [false, true] {
        let pipeline = @pipeline.check_carriers(
          asof_test_cursor(
            "[{\"from\":\"g\",\"shortest_path\":{\"source\":" +
            source +
            ",\"target\":" +
            target +
            (if sets { ",\"selection\":\"" + selection + "\"" } else { "" }) +
            ",\"direction\":\"both\",\"max_hops\":9007199254740992,\"max_output_rows\":1" +
            (if weighted { ",\"weight\":\"cost\"" } else { "" }) +
            "}}]",
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
        guard step.operation is @pipeline.Shortest(checked=operation, ..) else {
          fail("shortest")
        }
        let body = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
        let mut runtime = 0
        let mut unclosed = 0
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
          match shortest_execution_check(site).unwrap() {
            None => {
              unclosed += 1
              assert_true(
                site.requirement
                is @pipeline.ShortestRequirement(
                  ResolveShortestResources
                  | ResolveShortestProfile
                  | EnforceShortestOutputGuard
                ),
              )
            }
            Some(ShortestExecution(check)) => {
              runtime += 1
              assert_true(physical_equal(check.site, site))
              assert_true(physical_equal(check.operation, operation))
              assert_eq(check.input, @pipeline.Input(0))
              assert_eq(
                check.source_relation,
                if left {
                  Some(@pipeline.Input(1))
                } else {
                  None
                },
              )
              assert_eq(
                check.target_relation,
                if right {
                  Some(@pipeline.Input(1))
                } else {
                  None
                },
              )
              assert_eq(@graph.shortest_selection(check.operation), expected)
              assert_eq(
                @graph.shortest_max_hops(check.operation),
                9007199254740992.0,
              )
              assert_eq(
                @graph.shortest_weight(check.operation),
                if weighted {
                  Some(Unqualified("cost"))
                } else {
                  None
                },
              )
              let expected_phase = match site.requirement {
                @pipeline.ShortestRequirement(
                  AdmitShortestGraph
                  | RequireEndpointMembership
                  | ValidateAllNonnegativeFiniteWeights
                ) => BeforeOperationInputUse
                _ => BeforeOperationOutput
              }
              let expected_rule : ShortestRule = match site.requirement {
                @pipeline.ShortestRequirement(AdmitShortestGraph) =>
                  AdmitShortestInput
                @pipeline.ShortestRequirement(RequireEndpointMembership) =>
                  RequireEndpoints
                @pipeline.ShortestRequirement(
                  ValidateAllNonnegativeFiniteWeights
                ) => ValidateAllWeights
                @pipeline.ShortestRequirement(FoldPathCostsWithOverrange) =>
                  FoldCostsWithOverrange
                @pipeline.ShortestRequirement(RejectSelectedOverrangeAtomically) =>
                  RejectSelectedOverrange
                @pipeline.ShortestRequirement(SelectSimpleHopBoundedPaths) =>
                  SelectSimpleBoundedPaths
                @pipeline.ShortestRequirement(ApplyCanonicalPathTieBreaks) =>
                  ApplyPathTieBreaks
                @pipeline.ShortestRequirement(CanonicalShortestOutputOrder) =>
                  OrderOutputRows
                _ => {
                  fail("unexpected pending rule")
                  OrderOutputRows
                }
              }
              assert_eq(check.rule, expected_rule)
              assert_eq(
                operation_execution_phase(ShortestExecution(check)),
                expected_phase,
              )
              assert_eq(
                operation_execution_failure(ShortestExecution(check)),
                RejectOperationOutput,
              )
              for
                invalid in [
                  { ..site, step: 99, },
                  { ..site, group: 1, },
                  { ..site, index: -1, },
                ] {
                assert_true(
                  shortest_execution_check(invalid) is Err(ForeignOccurrence(_)),
                )
              }
            }
            _ => fail("wrong execution check")
          }
        }
        assert_eq(runtime, if weighted { 8 } else { 5 })
        assert_eq(unclosed, 3)
      }
    }
  }
}
