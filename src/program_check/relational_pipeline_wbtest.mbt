///|
test "formal check closes distinct representative selection append and join" {
  for
    operation in [
      "\"append\":{\"with\":\"again\"}", "\"distinct\":true", "\"distinct\":[\"id\",\"value\"]",
      "\"join\":{\"with\":\"again\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}",
      "\"join\":{\"with\":\"again\",\"kind\":\"left\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}",
      "\"join\":{\"with\":\"again\",\"kind\":\"full\",\"on\":\"value\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}",
      "\"join\":{\"with\":\"again\",\"kind\":\"semi\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}",
      "\"join\":{\"with\":\"again\",\"kind\":\"anti\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}",
      "\"dedupe_rows\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"value\":\"desc\"}]}",
      "\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"value\":\"desc\"}]}",
    ] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      second_steps="[{" + operation + ",\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
      second_join_capacity=operation.has_prefix("\"join\""),
    )
    let program = checked[0]
    let pipeline = unit_pipeline(program, 1).unwrap()
    let selected = @context.publication_row_limit_result(
      publication_selection(unit_publication_at(program, 1, 0).unwrap()),
    )
    assert_eq(
      @pipeline.publication_target(@publication.port_publication(selected.port)),
      @pipeline.lookup(pipeline, "selected").unwrap(),
    )
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut tie_checks = 0
    let mut append_checks = 0
    let mut join_limits = 0
    let mut join_identities = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(JoinIdentity(check))) {
        assert_eq(check.site.stage, 1)
        assert_true(physical_equal(check.site.pipeline, pipeline))
        assert_eq(
          check.input,
          @pipeline.Input(if check.side is Left { 0 } else { 1 }),
        )
        assert_eq(@evidence.key_field_count(check.key), 1)
        // Match tuple is value; row identity remains the independent id key.
        assert_true(
          @evidence.key_field_at(check.key, 0).unwrap().name
          is Unqualified("id"),
        )
        assert_true(@evidence.key_pending_count(check.key) > 0)
        assert_eq(
          @context.operation_execution_phase(JoinIdentity(check)),
          BeforeOperationInputUse,
        )
        assert_eq(
          @context.operation_execution_failure(JoinIdentity(check)),
          RejectOperationOutput,
        )
        join_identities += 1
      }
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(JoinOutputLimit(check))) {
        assert_eq(check.site.stage, 1)
        assert_true(physical_equal(check.site.pipeline, pipeline))
        assert_true(
          physical_equal(
            @step_bounds.join_limit_pipeline(check.limit),
            pipeline,
          ),
        )
        assert_eq(@step_bounds.join_limit_step(check.limit), 0)
        join_limits += 1
      }
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(AppendRows(check))) {
        assert_eq(check.site.stage, 1)
        assert_true(physical_equal(check.site.pipeline, pipeline))
        assert_eq(check.left, @pipeline.Input(0))
        assert_eq(check.right, @pipeline.Input(1))
        append_checks += 1
      }
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(DedupeTopTie(check))) {
        assert_eq(check.site.stage, 1)
        assert_true(physical_equal(check.site.pipeline, pipeline))
        assert_eq(check.input, @pipeline.Input(0))
        tie_checks += 1
      }
    }
    assert_eq(
      tie_checks,
      if operation.has_prefix("\"dedupe_rows\"") {
        1
      } else {
        0
      },
    )
    assert_eq(join_limits, if operation.has_prefix("\"join\"") { 1 } else { 0 })
    assert_eq(
      join_identities,
      if operation.contains("\"full\"") {
        2
      } else {
        0
      },
    )
    assert_eq(
      append_checks,
      if operation.has_prefix("\"append\"") {
        4
      } else {
        0
      },
    )
  }
}
