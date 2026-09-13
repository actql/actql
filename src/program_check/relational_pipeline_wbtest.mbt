///|
test "formal check closes distinct and representative selection" {
  for
    operation in [
      "\"distinct\":true", "\"distinct\":[\"id\",\"value\"]", "\"dedupe_rows\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"value\":\"desc\"}]}",
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
    for i in 0..<@context.operation_closure_count(closure) {
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
  }
}
