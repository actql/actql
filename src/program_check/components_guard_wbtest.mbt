///|
test "components author guards remain distinct from node proofs through imports" {
  for value in [1, 3, 20] {
    for parameter in [false, true] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        parameters=parameter,
        supplied=if parameter {
          Some(supplied_fixture("{\"n\":" + value.to_string() + "}"))
        } else {
          None
        },
        sga=true,
        graph_output_limit=Some(1000),
        graph_construction_limit=Some(1000),
        components_capacity_rows=Some(3),
        generated_rows=Some("[{\"id\":1},{\"id\":2},{\"id\":3}]"),
        producer_suffix=",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"components\":{\"kind\":\"weak\",\"max_output_rows\":" +
          (if parameter { "{\"$param\":\"n\"}" } else { value.to_string() }) +
          "}},{\"select\":[{\"id\":\"node_id\"},{\"value\":\"component_size\"}],\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=3,
      )
      let program = programs[0]
      let persistent = unit_components_limit_at(program, 0, 0).unwrap()
      assert_eq(unit_components_limit_count(program, 1), Some(0))
      let selected = components_limit_selection(persistent)
      let claim = components_limit_claim(persistent, OutputRows)
      assert_eq(
        @derivation.minimum_value(@wire.limit_minimum(claim)),
        value.min(3).to_int64(),
      )
      assert_eq(
        @derivation.minimum_candidate_count(@wire.limit_minimum(claim)),
        3,
      )
      assert_eq(
        @derivation.minimum_value(
          @wire.limit_minimum(components_limit_claim(persistent, InputNodes)),
        ),
        3L,
      )
      assert_eq(
        @step_bounds.components_limit_effective_maximum(
          selected.limits,
          OutputRows,
        ),
        value.min(3).to_int64(),
      )
      assert_eq(
        @step_bounds.components_limit_effective_maximum(
          selected.limits,
          InputNodes,
        ),
        3L,
      )
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut gates = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(ComponentsOutputGuard(check))) {
          assert_true(
            physical_equal(
              @step_bounds.components_limit_pipeline(check.limits),
              @step_bounds.components_limit_pipeline(selected.limits),
            ),
          )
          assert_true(
            physical_equal(
              @step_bounds.components_limit_claim(check.limits, OutputRows),
              @step_bounds.components_limit_claim(selected.limits, OutputRows),
            ),
          )
          assert_eq(
            @step_bounds.components_limit_guard_value(check.limits),
            Some(value.to_int64()),
          )
          assert_eq(
            @context.operation_execution_phase(ComponentsOutputGuard(check)),
            BeforeOperationOutput,
          )
          assert_eq(
            @context.operation_execution_failure(ComponentsOutputGuard(check)),
            RejectOperationOutput,
          )
          gates += 1
        }
      }
      assert_eq(gates, 3)
      let out = @encode.writer(100000, 10000, 100)
      @wire.emit_limit(claim, out)
      let text = @encode.finish(out)
      assert_true(text.contains("actql.guard.components-output"))
      assert_true(text.contains("$.steps[3].components.max_output_rows"))
      assert_false(text.contains("checked-step:"))
    }
  }
}
