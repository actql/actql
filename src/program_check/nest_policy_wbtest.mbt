///|
test "SourceView nest retains both contributor policies after hiding child output" {
  for guard_text in ["", ",\"max_items\":3"] {
    let program = checked_direct_program_fixture(nest_guard=Some(guard_text))
    let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 2)
    let input_indices = []
    for index in 0..<publication_policy_source_count(policy) {
      let source = publication_policy_source_at(policy, index).unwrap()
      assert_true(physical_equal(source.subject.owner, program.identity))
      assert_eq(source.subject.stage, 0)
      input_indices.push(source.subject.input)
    }
    input_indices.sort()
    // Authored source inventory: right, unused, remote.
    assert_eq(input_indices, [0, 2])
    assert_eq(publication_policy_nest_count(policy), 1)
    let retained = publication_policy_nest_at(policy, 0).unwrap()
    assert_eq(retained.step, 2)
    assert_eq(retained.unknown_provenance, guard_text != "")
    assert_eq(@nest.with_name(retained.operation), "children")
    assert_eq(@nest.into(retained.operation), "items")
    assert_true(publication_policy_nest_at(policy, -1) is None)
    assert_true(publication_policy_nest_at(policy, 1) is None)
    assert_eq(unit_nest_limit_count(program, 0), Some(1))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(NestExecution(check))) {
        checks += 1
        assert_true(physical_equal(check.operation, retained.operation))
        assert_eq(check.site.step, retained.step)
      }
    }
    assert_eq(checks, 2)
    // The third acquisition is checked but does not contribute to this Result.
    assert_eq(source_execution_count(program), 15)
  }
}
