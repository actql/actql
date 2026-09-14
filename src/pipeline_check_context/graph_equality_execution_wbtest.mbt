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
  for name in ["graphs_equal", "graph_diff", "apply_graph_delta"] {
    let ordinal = if name == "apply_graph_delta" { 1 } else { 0 }
    let text = if name == "apply_graph_delta" {
      "[{\"graph_diff\":{\"with\":\"b\"},\"from\":\"a\",\"as\":\"changes\"},{\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"},\"from\":\"a\"}]"
    } else {
      "[{\"" + name + "\":{\"with\":\"b\"},\"from\":\"a\"}]"
    }
    let pipeline = @pipeline.check_carriers(
      asof_test_cursor(text),
      [("a", graph), ("b", graph)],
      None,
      None,
      {
        max_steps: 2,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap()
    let step = @pipeline.step_at(pipeline, ordinal).unwrap()
    let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let policy = sequence_limit_policy(false)
    let bind = fn(site : OperationRequirementSite) {
      if name == "graphs_equal" {
        graph_equality_execution_check(site, policy)
      } else if name == "graph_diff" {
        graph_diff_execution_check(site, policy)
      } else {
        graph_apply_execution_check(site, policy)
      }
    }
    for index in 0..<@pipeline.operation_obligations_count(group) {
      let site : OperationRequirementSite = {
        stage: 0,
        producer_visit: 0,
        step: ordinal,
        group: 0,
        index,
        pipeline,
        obligations: group,
        requirement: @pipeline.operation_obligations_at(group, index).unwrap(),
      }
      if site.requirement is @pipeline.EqualityRequirement(ResolveSgaProfile) ||
        site.requirement is @pipeline.DiffRequirement(ResolveSgaProfile) ||
        site.requirement is @pipeline.ApplyRequirement(ResolveSgaProfile) {
        assert_true(bind(site) is Ok(None))
        continue
      }
      let (owner, selected, left, right) = match bind(site) {
        Ok(Some(GraphEqualityExecution(check))) =>
          (check.site, check.policy, check.left, check.right)
        Ok(Some(GraphDiffExecution(check))) =>
          (check.site, check.policy, check.base, check.target)
        Ok(Some(GraphApplyExecution(check))) =>
          (check.site, check.policy, check.base, check.delta)
        _ => fail("missing comparison requirement")
      }
      assert_true(physical_equal(owner, site))
      assert_true(physical_equal(selected, policy))
      assert_eq(left, @pipeline.Input(0))
      assert_eq(
        right,
        if ordinal == 1 {
          @pipeline.Step(0)
        } else {
          @pipeline.Input(1)
        },
      )
      assert_true(
        bind({ ..site, index: 99, }) is Err(ForeignOccurrence(failed)) &&
        failed == ordinal,
      )
      assert_true(bind({ ..site, step: 99, }) is Err(ForeignOccurrence(99)))
      assert_true(
        bind({
          ..site,
          index: (index + 1) %
          (@pipeline.operation_obligations_count(group) - 1),
        })
        is Err(ForeignOccurrence(failed)) &&
        failed == ordinal,
      )
    }
  }
}
