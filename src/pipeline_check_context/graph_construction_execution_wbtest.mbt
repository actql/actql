///|
fn property_execution_steps() -> String {
  (
    #|[{"values":{"schema":{"id":{"type":"number","nullable":true}},"rows":[{"id":1}]},"as":"seed"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"]},{"name":"Other","from":"seed","key":["id"]}],"edges":[{"name":"E","from":"seed","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]}}]},"as":"g"}]
  )
}

///|
fn property_execution_pipeline() -> @pipeline.CheckedPipeline {
  @pipeline.check_carriers(
    asof_test_cursor(property_execution_steps()),
    [],
    None,
    None,
    {
      max_steps: 2,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn property_execution_site(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
) -> OperationRequirementSite {
  let step = @pipeline.step_at(pipeline, 1).unwrap()
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  {
    stage: 0,
    producer_visit: 0,
    step: 1,
    group: 0,
    index,
    pipeline,
    obligations,
    requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
  }
}

///|
fn property_execution_policy() -> @policy.Policy {
  let body =
    #|{"max_aggregate_array_items":7,"max_artifact_bytes":7,"max_artifact_rows":7,"max_effect_items":7,"max_graph_construction_edges":5,"max_graph_construction_input_rows":7,"max_graph_construction_nodes":3,"max_graph_input_edges":7,"max_graph_input_nodes":7,"max_graph_output_rows":7,"max_graph_paths":7,"max_infer_items":7,"max_model_input_tokens_per_item":7,"max_model_request_bytes_per_item":7,"max_model_total_duration_ms":7,"max_nested_value_bytes":7,"max_nested_value_depth":7,"max_relation_output_rows":7,"max_temporal_matches_per_key":3,"max_temporal_output_rows":7,"version":"actql-capacity-host-policy/0.1"}
  @policy.admit(
    @wire_utf8.encode(body),
    // Independently hash the authored canonical policy, not product output.
    "sha256:68b3117e9107a0ebe3700bbaf979f3ba0a1e1bede3579ebbd38eb152d97e6029",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
test "keyed construction requirements retain exact owners repeated inputs and shared policy ceilings" {
  let pipeline = property_execution_pipeline()
  let step = @pipeline.step_at(pipeline, 1).unwrap()
  guard step.operation is @pipeline.GraphConstruction(checked=operation, ..) else {
    fail("keyed constructor")
  }
  let expected : Array[GraphConstructionRule?] = [
    Some(AdmitPropertyInputRows),
    Some(RejectDuplicateKeys),
    Some(ExcludeNullKeysAndMissingEndpoints),
    Some(EnforcePropertyConstructionEnvelope),
    None,
  ]
  let policy = property_execution_policy()
  for index, rule in expected {
    let site = property_execution_site(pipeline, index)
    match (graph_construction_execution_check(site, policy).unwrap(), rule) {
      (Some(GraphConstructionExecution(check)), Some(rule)) => {
        assert_eq(check.rule, rule)
        assert_true(physical_equal(check.site, site))
        assert_true(physical_equal(check.step, step))
        assert_true(physical_equal(check.operation, operation))
        assert_eq(@pipeline.input_occurrence_count(check.step), 3)
        for i in 0..<3 {
          assert_true(
            @pipeline.input_occurrence_at(check.step, i)
            is Some({ role: Sample(n), target: Step(0), }) &&
            n == i,
          )
        }
        assert_eq(
          operation_execution_phase(GraphConstructionExecution(check)),
          if index == 0 {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          operation_execution_failure(GraphConstructionExecution(check)),
          RejectOperationOutput,
        )
        if index == 3 {
          let envelope = check.envelope.unwrap()
          assert_true(physical_equal(envelope.policy, policy))
          for
            (ceiling, field, value) in [
              (envelope.input_rows, "max_graph_construction_input_rows", 7L),
              (envelope.output_nodes, "max_graph_construction_nodes", 3L),
              (envelope.output_edges, "max_graph_construction_edges", 5L),
            ] {
            assert_true(physical_equal(@policy.ceiling_policy(ceiling), policy))
            assert_eq(@policy.ceiling_field(ceiling), field)
            assert_eq(@policy.ceiling_value(ceiling), value)
          }
        } else {
          assert_true(check.envelope is None)
        }
        assert_true(
          direct_execution_candidate(site, policy, Ok(None), Ok(None))
          is Ok(Some(GraphConstructionExecution(_))),
        )
        let foreign = property_execution_site(
          property_execution_pipeline(),
          index,
        )
        for
          bad in [
            { ..site, index: 99, },
            { ..site, step: 99, },
            { ..site, group: 1, },
            { ..site, obligations: foreign.obligations, },
          ] {
          assert_true(
            graph_construction_execution_check(bad, policy)
            is Err(ForeignOccurrence(_)),
          )
        }
      }
      (None, None) => assert_eq(index, 4)
      _ => fail("foreign construction rule")
    }
  }
  // Missing ceilings are unresolved, not permission to run without limits.
  assert_true(
    graph_construction_execution_check(
      property_execution_site(pipeline, 3),
      sequence_limit_policy(false),
    )
    is Ok(None),
  )
}
