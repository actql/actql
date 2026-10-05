///|
fn delta_execution_pipeline(body : String) -> @pipeline.CheckedPipeline {
  let producer = property_execution_pipeline()
  let graph = @pipeline.carrier_at(producer, @pipeline.Step(1)).unwrap()
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("delta"),
          Some(@contract.primitive(@contract.JsonType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=16,
    ).unwrap(),
  )
  @pipeline.check_carriers(
    asof_test_cursor(body),
    [("g", graph), ("other", graph), ("changes", rows)],
    None,
    None,
    {
      max_steps: 5,
      max_work: 1000000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn delta_execution_site(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
) -> OperationRequirementSite {
  let step = @pipeline.step_at(pipeline, 0).unwrap()
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  {
    stage: 0,
    producer_visit: 0,
    step: 0,
    group: 0,
    index,
    pipeline,
    obligations,
    requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
  }
}

///|
test "Delta requirements separate the static profile from exact typed runtime operand roles" {
  let policy = property_execution_policy()
  for
    (body, right, rules) in [
      (
        "[{\"from\":\"g\",\"graph_diff\":{\"with\":\"other\"}}]",
        @pipeline.Input(1),
        [AdmitGraphOperands, RequireDeltaResources, EnforceDeltaRows],
      ),
      (
        "[{\"from\":\"g\",\"graph_diff\":{\"with\":\"g\"}}]",
        @pipeline.Input(0),
        [AdmitGraphOperands, RequireDeltaResources, EnforceDeltaRows],
      ),
      (
        "[{\"from\":\"g\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}}]",
        @pipeline.Input(2),
        [
          AdmitGraphOperands,
          RequireDeltaResources,
          RequireExactlyOneDeltaRow,
          AdmitCompleteDeltaActions,
          CheckExactBaseBeforeTarget,
        ],
      ),
    ] {
    let pipeline = delta_execution_pipeline(body)
    let step = @pipeline.step_at(pipeline, 0).unwrap()
    guard step.operation is @pipeline.GraphDelta(checked=operation, ..) else {
      abort("missing checked Delta owner")
    }
    assert_eq(@graph.delta_pending_count(operation), rules.length())
    for index, rule in rules {
      let site = delta_execution_site(pipeline, index)
      if rule == AdmitGraphOperands {
        assert_eq(
          @pipeline.operation_profile_requirement(site.requirement),
          Some(@pipeline.PropertyGraph),
        )
        assert_true(graph_delta_execution_check(site, policy) is Ok(None))
        assert_true(
          direct_execution_candidate(site, policy, Ok(None), Ok(None))
          is Ok(None),
        )
        continue
      }
      guard graph_delta_execution_check(site, policy)
        is Ok(Some(GraphDeltaExecution(check))) else {
        abort("Delta runtime requirement was left unresolved")
      }
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.step, step))
      assert_true(physical_equal(check.operation, operation))
      assert_true(physical_equal(check.policy, policy))
      assert_eq(check.left, @pipeline.Input(0))
      assert_eq(check.right, right)
      assert_eq(check.rule, rule)
      assert_eq(
        operation_execution_failure(GraphDeltaExecution(check)),
        RejectOperationOutput,
      )
      assert_eq(
        operation_execution_phase(GraphDeltaExecution(check)),
        if rule == EnforceDeltaRows || rule == CheckExactBaseBeforeTarget {
          BeforeOperationOutput
        } else {
          BeforeOperationInputUse
        },
      )
      guard direct_execution_candidate(site, policy, Ok(None), Ok(None))
        is Ok(Some(GraphDeltaExecution(selected))) else {
        abort(
          "Program resolution dispatch did not select the typed Delta check",
        )
      }
      assert_true(physical_equal(selected.site, site))
      assert_true(physical_equal(selected.operation, operation))
    }
  }
}

///|
test "Delta execution binding refuses foreign owners indices and non-Body occurrences" {
  let body = "[{\"from\":\"g\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}}]"
  let pipeline = delta_execution_pipeline(body)
  let foreign = delta_execution_pipeline(body)
  let policy = property_execution_policy()
  for index in 0..<5 {
    let site = delta_execution_site(pipeline, index)
    let other = delta_execution_site(foreign, index)
    for
      bad in [
        { ..site, pipeline: foreign, },
        { ..site, obligations: other.obligations, },
        { ..site, step: 99, },
        { ..site, group: 1, },
        { ..site, index: 99, },
        { ..site, index: (index + 1) % 5, },
        { ..site, requirement: other.requirement, index: (index + 1) % 5, },
      ] {
      assert_true(
        graph_delta_execution_check(bad, policy) is Err(ForeignOccurrence(_)),
      )
      assert_true(
        direct_execution_candidate(bad, policy, Ok(None), Ok(None))
        is Err(ForeignOccurrence(_)),
      )
    }
  }
  let unrelated = property_execution_site(property_execution_pipeline(), 0)
  assert_true(graph_delta_execution_check(unrelated, policy) is Ok(None))
}
