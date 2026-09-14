///|
test "formal structural Graphs retain every fold and resource owner through Result imports" {
  for
    (name, references, strategy, expression, folds) in [
      ("graft_graph", "\"g\"", "", "id", 1),
      ("union_graphs", "\"g\"", "number_sum", "id", 1),
      ("union_graphs", "[\"g\",\"g\",\"g\"]", "number_mean", "id", 3),
      ("union_graphs", "[\"g\"]", "set_union", "[id]", 1),
      ("subtract_graphs", "\"g\"", "", "id", 1),
      ("subtract_graphs", "\"g\"", "exact_equal", "id", 1),
      ("subtract_graphs", "\"g\"", "number_sum", "id", 1),
      ("subtract_graphs", "\"g\"", "set_difference", "[id]", 1),
    ] {
    for empty in [false, true] {
      let programs : Array[CheckedProgram] = []
      let suffix = ",{\"graph\":{\"nodes\":{\"from\":\"derived\",\"id\":\"id\",\"fields\":[\"value\"]},\"edges\":{\"from\":\"seed\",\"source\":\"id\",\"target\":\"id\",\"fields\":[]}},\"as\":\"g\"},{\"" +
        name +
        "\":{\"with\":" +
        references +
        (if strategy == "" {
          ""
        } else {
          ",\"merge\":{\"node_properties\":{\"value\":\"" + strategy + "\"}}"
        }) +
        "}},{\"node_rows\":true},{\"select\":[\"id\",\"value\"],\"as\":\"projected\"}"
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        generated_rows=Some(
          if empty {
            "[]"
          } else {
            "[{\"id\":1},{\"id\":2}]"
          },
        ),
        producer_expression=expression,
        producer_suffix=suffix,
        producer_result_from="projected",
        extra_step_budget=4,
      )
      let program = programs[0]
      assert_eq(unit_count(program), 2)
      let step = @pipeline.step_at(program.units[0].pipeline, 3).unwrap()
      assert_eq(
        @pipeline.operation_obligation_group_count(step.operation),
        folds,
      )
      let closure = @context.stage_requirement_operations(program.requirements)
      let mut resources = 0
      let mut policies = 0
      let mut apply = 0
      let mut endpoint = 0
      let mut resource_policy : @policy.Policy? = None
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(GraphStructuralExecution(check))) {
          assert_true(physical_equal(check.step, step))
          assert_true(
            physical_equal(check.site.pipeline, program.units[0].pipeline),
          )
          assert_eq(check.site.step, 3)
          if resource_policy is Some(policy) {
            assert_true(physical_equal(policy, check.policy))
          } else {
            resource_policy = Some(check.policy)
          }
          assert_eq(check.right, @pipeline.Step(2))
          assert_eq(
            check.left,
            if check.site.group == 0 {
              @context.StructuralInput(@pipeline.Step(2))
            } else {
              @context.UnionAccumulator(check.site.group - 1)
            },
          )
          match check.rule {
            RequireStructuralResources => {
              resources += 1
              assert_eq(@context.graph_structural_resource_count(check), 3)
              assert_eq(
                @context.operation_execution_phase(
                  GraphStructuralExecution(check),
                ),
                BeforeOperationInputUse,
              )
            }
            PreserveOperandPolicies => policies += 1
            ApplyPropertyStrategies => apply += 1
            CloseResultEndpoints => endpoint += 1
            _ => ()
          }
          assert_eq(
            @context.operation_execution_failure(
              GraphStructuralExecution(check),
            ),
            RejectOperationOutput,
          )
        }
      }
      assert_eq(resources, 3 * folds)
      assert_eq(policies, 3 * folds)
      assert_eq(apply, if strategy == "" { 0 } else { 3 * folds })
      assert_eq(endpoint, if name == "subtract_graphs" { 3 } else { 0 })
    }
  }
}
