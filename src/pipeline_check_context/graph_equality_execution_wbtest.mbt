///|
test "Graph comparison bindings reject mismatched occurrences and leave profile selection separate" {
  let fields = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    fields,
    fields,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let pipeline = @pipeline.check_carriers(
    asof_test_cursor("[{\"graphs_equal\":{\"with\":\"b\"},\"from\":\"a\"}]"),
    [("a", graph), ("b", graph)],
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
  let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  let policy = sequence_limit_policy(false)
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
    if site.requirement is @pipeline.EqualityRequirement(ResolveSgaProfile) {
      assert_true(graph_equality_execution_check(site, policy) is Ok(None))
      continue
    }
    guard graph_equality_execution_check(site, policy)
      is Ok(Some(GraphEqualityExecution(check))) else {
      fail("missing comparison requirement")
    }
    assert_true(physical_equal(check.site, site))
    assert_true(physical_equal(check.policy, policy))
    assert_eq(check.left, @pipeline.Input(0))
    assert_eq(check.right, @pipeline.Input(1))
    assert_true(
      graph_equality_execution_check({ ..site, index: 99, }, policy)
      is Err(ForeignOccurrence(0)),
    )
    assert_true(
      graph_equality_execution_check({ ..site, step: 99, }, policy)
      is Err(ForeignOccurrence(99)),
    )
    assert_true(
      graph_equality_execution_check(
        { ..site, index: (index + 1) % 3, },
        policy,
      )
      is Err(ForeignOccurrence(0)),
    )
  }
}
