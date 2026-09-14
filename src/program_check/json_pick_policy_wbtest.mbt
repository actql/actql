///|
test "SourceView json pick retains structural path and exact shape validation" {
  for path in ["[\"first\"]", "[\"first\",\"leaf\"]"] {
    let program = checked_direct_program_fixture(json_pick_path=path)
    let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_json_pick_count(policy), 1)
    let retained = publication_policy_json_pick_at(policy, 0).unwrap()
    assert_eq(retained.step, 1)
    assert_eq(
      @relation.json_pick_path_count(retained.operation),
      if path == "[\"first\"]" {
        1
      } else {
        2
      },
    )
    assert_eq(@relation.json_pick_path_at(retained.operation, 0), Some("first"))
    assert_true(
      !publication_policy_derivation_at(policy, 0).unwrap().unknown_provenance,
    )
    assert_true(publication_policy_json_pick_at(policy, -1) is None)
    assert_true(publication_policy_json_pick_at(policy, 1) is None)
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(JsonPickExecution(check))) {
        checks += 1
        assert_true(physical_equal(check.operation, retained.operation))
        assert_eq(check.site.step, retained.step)
        assert_eq(
          @context.operation_execution_failure(JsonPickExecution(check)),
          RejectOperationOutput,
        )
      }
    }
    assert_eq(checks, 1)
  }
}
