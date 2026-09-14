///|
test "structural execution retains binary roles ordered accumulators and resource requirements" {
  let policy = sequence_limit_policy(false)
  let bind = site => graph_structural_execution_check(site, policy)
  let number = @contract.primitive(NumberType, nullable=false)
  let array = @contract.array_contract(
    number,
    nullable=true,
    max_items=Some(2L),
  ).unwrap()
  let properties = @carrier.rows(
    [(Unqualified("n"), Some(number)), (Unqualified("t"), Some(array))],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  let graph = @carrier.graph(
    number,
    properties,
    properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  for
    (name, with_text, folds, repeated) in [
      ("graft_graph", "\"b\"", 1, false),
      ("subtract_graphs", "\"a\"", 1, false),
      ("union_graphs", "\"b\"", 1, false),
      ("union_graphs", "[\"a\"]", 1, true),
      ("union_graphs", "[\"b\",\"a\",\"b\"]", 3, true),
    ] {
    for strategies in [false, true] {
      if name == "graft_graph" && strategies {
        continue
      }
      let merge = if strategies {
        ",\"merge\":{\"node_properties\":{\"n\":\"number_sum\",\"t\":\"set_difference\"},\"edge_properties\":{\"n\":\"exact_equal\"}}"
      } else {
        ""
      }
      let pipeline = @pipeline.check_carriers(
        asof_test_cursor(
          "[{\"from\":\"a\",\"" +
          name +
          "\":{\"with\":" +
          with_text +
          merge +
          "}}]",
        ),
        [("a", graph), ("b", graph)],
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
        @pipeline.operation_obligation_group_count(step.operation),
        folds,
      )
      let expected : Array[GraphStructuralRule] = [
        AdmitStructuralInputs,
        CompareIdentityRecords,
        RequirePropertyEquality,
        PreserveOperandPolicies,
        RequireStructuralResources,
      ]
      if name == "subtract_graphs" {
        expected.push(SubtractMatchingRecords)
        expected.push(CloseResultEndpoints)
      } else {
        expected.push(RetainOneSidedRecords)
      }
      if strategies {
        expected.push(ApplyPropertyStrategies)
        expected.push(ValidateNumericResults)
        expected.push(ValidateSetResults)
      }
      for fold in 0..<folds {
        let group = @pipeline.operation_obligation_group_at(
          step.operation,
          fold,
        ).unwrap()
        let actual : Array[GraphStructuralRule] = []
        let mut unresolved = 0
        for index in 0..<@pipeline.operation_obligations_count(group) {
          let site : OperationRequirementSite = {
            stage: 0,
            producer_visit: 0,
            step: 0,
            group: fold,
            index,
            pipeline,
            obligations: group,
            requirement: @pipeline.operation_obligations_at(group, index).unwrap(),
          }
          let result = bind(site)
          if site.requirement
            is @pipeline.StructuralRequirement(ResolveSgaProfile) {
            assert_true(result is Ok(None))
            unresolved += 1
            continue
          }
          guard result is Ok(Some(GraphStructuralExecution(check))) else {
            fail("missing structural binding")
          }
          actual.push(check.rule)
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.policy, policy))
          if check.rule == RequireStructuralResources {
            assert_eq(graph_structural_resource_count(check), 3)
            assert_eq(
              graph_structural_resource_at(check, 0),
              Some(CompositionWork),
            )
            assert_eq(
              graph_structural_resource_at(check, 1),
              Some(ValueAndTemporaryBytes),
            )
            assert_eq(
              graph_structural_resource_at(check, 2),
              Some(RetainedCompositionState),
            )
            assert_true(graph_structural_resource_at(check, -1) is None)
            assert_true(graph_structural_resource_at(check, 3) is None)
          } else {
            assert_eq(graph_structural_resource_count(check), 0)
            assert_true(graph_structural_resource_at(check, 0) is None)
          }
          assert_true(physical_equal(check.step, step))
          assert_eq(
            check.left,
            if fold == 0 {
              StructuralInput(@pipeline.Input(0))
            } else {
              UnionAccumulator(fold - 1)
            },
          )
          let right = if name == "subtract_graphs" ||
            (repeated && (folds == 1 || fold == 1)) {
            0
          } else {
            1
          }
          assert_eq(check.right, @pipeline.Input(right))
          if step.operation is @pipeline.GraphUnion(union) {
            assert_true(
              physical_equal(
                check.operation,
                @graph.union_fold_at(union, fold).unwrap(),
              ),
            )
          }
          assert_eq(
            operation_execution_phase(GraphStructuralExecution(check)),
            if check.rule == AdmitStructuralInputs ||
              check.rule == RequireStructuralResources {
              BeforeOperationInputUse
            } else {
              BeforeOperationOutput
            },
          )
          assert_eq(
            operation_execution_failure(GraphStructuralExecution(check)),
            RejectOperationOutput,
          )
          for
            (side, count) in [
              (@schema.Left, if strategies { 2 } else { 0 }),
              (@schema.Right, if strategies { 1 } else { 0 }),
            ] {
            assert_eq(
              @graph.structural_strategy_count(check.operation, side),
              count,
            )
            assert_true(
              @graph.structural_strategy_at(check.operation, side, -1) is None,
            )
            assert_true(
              @graph.structural_strategy_at(check.operation, side, count)
              is None,
            )
            for i in 0..<count {
              let selected = @graph.structural_strategy_at(
                check.operation,
                side,
                i,
              ).unwrap()
              assert_true(
                physical_equal(
                  selected,
                  @graph.structural_strategy_at(check.operation, side, i).unwrap(),
                ),
              )
              assert_eq(selected.name, if i == 0 { "n" } else { "t" })
              assert_eq(
                selected.strategy,
                if side == @schema.Right {
                  @graph.ExactEqual
                } else if i == 0 {
                  @graph.NumberSum
                } else {
                  @graph.SetDifference
                },
              )
            }
          }
          assert_true(bind({ ..site, step: 99, }) is Err(ForeignOccurrence(99)))
          assert_true(
            bind({ ..site, group: fold + 1, }) is Err(ForeignOccurrence(0)),
          )
          assert_true(bind({ ..site, index: 99, }) is Err(ForeignOccurrence(0)))
        }
        assert_eq(actual, expected)
        assert_eq(unresolved, 1)
      }
    }
  }
}
