///|
test "mean bindings retain positional samples policies and exact pending semantics" {
  let policy = sequence_limit_policy(false)
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.with_nullability(number, true)
  let properties = @carrier.rows(
    [(Unqualified("n"), Some(nullable))],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let graph = @carrier.graph(
    number,
    properties,
    properties,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let expected : Array[GraphMeanRule] = [
    AdmitMeanSamples,
    CompareMeanSupport,
    CloseMeanEndpoints,
    CheckMeanLabels,
    ApplyMeanProperties,
    RoundMeanOnce,
    ValidateMeanFiniteResults,
    OrderMeanIdentities,
    PreserveMeanDependencies,
    RequireMeanResources,
  ]
  for missing in ["exclude", "zero"] {
    for nulls in ["exclude", "zero", "fail"] {
      for
        (weights, first_weight) in [
          ("[0,1,2]", 0.0),
          (
            "[1.7976931348623157e308,1.7976931348623157e308,0]", 1.7976931348623157e308,
          ),
        ] {
        let pipeline = @pipeline.check_carriers(
          asof_test_cursor(
            "[{\"mean_graphs\":{\"with\":[\"a\",\"b\",\"a\"],\"weights\":" +
            weights +
            ",\"support\":{\"nodes\":1,\"edges\":0.5},\"properties\":{\"nodes\":{\"n\":{\"mean\":{\"missing\":\"" +
            missing +
            "\",\"nulls\":\"" +
            nulls +
            "\"}}},\"edges\":{\"n\":\"exact_equal\"}}},\"as\":\"m\"}]",
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
        let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
        assert_eq(@pipeline.operation_obligations_count(group), 11)
        for index in 0..<11 {
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
          let result = direct_execution_candidate(
            site,
            policy,
            Ok(None),
            Ok(None),
          )
          if index == 10 {
            assert_true(result is Ok(None))
            continue
          }
          guard result is Ok(Some(GraphMeanExecution(check))) else {
            fail("missing mean semantic binding")
          }
          assert_eq(check.rule, expected[index])
          assert_eq(
            graph_mean_resource_count(check),
            if index == 9 {
              4
            } else {
              0
            },
          )
          assert_true(graph_mean_resource_at(check, -1) is None)
          assert_true(graph_mean_resource_at(check, 4) is None)
          if index == 9 {
            let resources : Array[GraphMeanResource] = [
              SampleWork,
              ExactArithmeticWork,
              ValueAndTemporaryBytes,
              RetainedMeanState,
            ]
            for i in 0..<resources.length() {
              assert_eq(graph_mean_resource_at(check, i), Some(resources[i]))
            }
          } else {
            assert_true(graph_mean_resource_at(check, 0) is None)
          }
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.step, step))
          assert_true(physical_equal(check.policy, policy))
          guard step.operation is @pipeline.GraphMean(operation) else {
            fail("expected generator")
          }
          assert_true(physical_equal(check.operation, operation))
          assert_eq(graph_mean_sample_count(check), 3)
          assert_true(graph_mean_sample_at(check, -1) is None)
          assert_true(graph_mean_sample_at(check, 3) is None)
          let options = @graph.mean_options(operation)
          for i in 0..<3 {
            let (input, weight) = graph_mean_sample_at(check, i).unwrap()
            assert_true(
              physical_equal(
                input,
                @pipeline.input_occurrence_at(step, i).unwrap(),
              ),
            )
            assert_eq(input.role, @pipeline.Sample(i))
            assert_eq(input.target, @pipeline.Input(if i == 1 { 1 } else { 0 }))
            assert_eq(weight, @graph.mean_weight_at(options, i).unwrap())
          }
          assert_eq(graph_mean_sample_at(check, 0).unwrap().1, first_weight)
          for entity in [@graph.Nodes, @graph.Edges] {
            assert_eq(@graph.mean_property_count(options, entity), 1)
            assert_true(@graph.mean_property_at(options, entity, -1) is None)
            assert_true(@graph.mean_property_at(options, entity, 1) is None)
            let property = @graph.mean_property_at(options, entity, 0).unwrap()
            assert_true(
              physical_equal(
                property,
                @graph.mean_properties(options, entity)[0],
              ),
            )
            assert_eq(property.name, "n")
            assert_eq(
              property.strategy,
              if entity == @graph.Edges {
                @graph.EqualValues
              } else {
                @graph.WeightedMean(
                  if missing == "zero" {
                    @graph.ZeroMissing
                  } else {
                    @graph.ExcludeMissing
                  },
                  match nulls {
                    "zero" => @graph.ZeroNull
                    "fail" => @graph.FailNull
                    _ => @graph.ExcludeNull
                  },
                )
              },
            )
          }
          assert_eq(
            operation_execution_phase(GraphMeanExecution(check)),
            if index == 0 || index == 9 {
              BeforeOperationInputUse
            } else {
              BeforeOperationOutput
            },
          )
          assert_eq(
            operation_execution_failure(GraphMeanExecution(check)),
            RejectOperationOutput,
          )
          assert_true(
            graph_mean_execution_check({ ..site, step: 99, }, policy)
            is Err(ForeignOccurrence(99)),
          )
          assert_true(
            graph_mean_execution_check({ ..site, group: 1, }, policy)
            is Err(ForeignOccurrence(0)),
          )
          assert_true(
            graph_mean_execution_check({ ..site, index: 99, }, policy)
            is Err(ForeignOccurrence(0)),
          )
        }
      }
    }
  }
}
