///|
test "graph construction binds each semantic rule to ordered input occurrences" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.string_contract(nullable=false).unwrap()
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(number)),
        (Unqualified("src"), Some(number)),
        (Unqualified("dst"), Some(number)),
        (Unqualified("edge_type"), Some(text)),
      ],
      field_set=Closed,
      max_fields=4,
      max_name_bytes=100,
    ).unwrap(),
  )
  for
    (body, explicit, different, label_completion) in [
      (
        "{\"graph\":{\"nodes\":{\"from\":\"r\",\"id\":\"id\"},\"edges\":{\"from\":\"r\",\"source\":\"src\",\"target\":\"dst\"}},\"as\":\"g\"}",
        true, false, false,
      ),
      (
        "{\"graph\":{\"nodes\":{\"from\":\"r\",\"id\":\"id\"},\"edges\":{\"from\":\"other\",\"source\":\"src\",\"target\":\"dst\"}},\"as\":\"g\"}",
        true, true, false,
      ),
      (
        "{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"from\":\"r\"}", false,
        false, true,
      ),
      (
        "{\"graph\":{\"source\":\"src\",\"target\":\"dst\",\"label\":\"edge_type\"},\"from\":\"r\"}",
        false, false, false,
      ),
    ] {
    let pipeline = @pipeline.check_carriers(
      asof_test_cursor("[" + body + "]"),
      [("r", rows), ("other", rows)],
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
    guard step.operation is @pipeline.GraphConstruction(checked=operation, ..) else {
      fail("construction")
    }
    let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let expected : Array[GraphConstructionRule?] = [
      Some(AdmitInputRows),
      Some(CollapseEqualPayloads),
      Some(RejectPayloadConflicts),
      None,
      None,
      Some(JournalEndpoints),
      Some(if explicit { CloseDeclaredEndpoints } else { DeriveEndpointNodes }),
    ]
    if label_completion {
      expected.push(Some(JournalLabels))
    }
    assert_eq(@pipeline.operation_obligations_count(group), expected.length())
    for index, rule in expected {
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
      match
        (
          graph_construction_execution_check(site, sequence_limit_policy(false)).unwrap(),
          rule,
        ) {
        (Some(GraphConstructionExecution(check)), Some(expected_rule)) => {
          assert_eq(check.rule, expected_rule)
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.step, step))
          assert_true(physical_equal(check.operation, operation))
          assert_eq(
            check.nodes,
            if explicit {
              Some(@pipeline.Input(0))
            } else {
              None
            },
          )
          assert_eq(check.edges, @pipeline.Input(if different { 1 } else { 0 }))
          assert_eq(
            @pipeline.input_occurrence_count(check.step),
            if explicit {
              2
            } else {
              1
            },
          )
          assert_eq(
            operation_execution_failure(GraphConstructionExecution(check)),
            RejectOperationOutput,
          )
          assert_eq(
            operation_execution_phase(GraphConstructionExecution(check)),
            if index == 0 {
              BeforeOperationInputUse
            } else {
              BeforeOperationOutput
            },
          )
          assert_true(
            graph_construction_execution_check(
              { ..site, index: 99, },
              sequence_limit_policy(false),
            )
            is Err(ForeignOccurrence(0)),
          )
          assert_true(
            graph_construction_execution_check(
              { ..site, step: 99, },
              sequence_limit_policy(false),
            )
            is Err(ForeignOccurrence(99)),
          )
          assert_true(
            direct_execution_candidate(
              site,
              sequence_limit_policy(false),
              Ok(None),
              Ok(None),
            )
            is Ok(Some(GraphConstructionExecution(_))),
          )
        }
        (None, None) => assert_true(index == 3 || index == 4)
        _ => fail("wrong rule")
      }
    }
  }
}
