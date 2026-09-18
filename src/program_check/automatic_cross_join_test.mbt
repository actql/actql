///|
test "standard check constructs cross join product capacity" {
  let (_, _, environment, _, base) = public_input_fixture()
  let limits : @program_check.CheckLimits = {
    input: { ..base.input, max_stages: 1, },
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, stages: 1, steps: 10, },
    },
  }
  let source =
    #|{"version":"actql/0.1","id":"cross","stages":[{"id":"crossed","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"left_raw"},{"from":"left_raw","distinct":["id"],"as":"left_rows"},{"values":{"schema":{"tag":{"type":"string","nullable":false}},"rows":[{"tag":"a"},{"tag":"b"}]},"as":"right_raw"},{"from":"right_raw","distinct":["tag"],"as":"right_rows"},{"from":"left_rows","cross_join":{"with":"right_rows","select":{"id":"left.id","tag":"right.tag"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","tag"]}}}],"results":{"out":{"from":{"stage":"crossed","result":"r"}}}}
  let checked = public_checked(
    @program_check.check_document(
      source,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  let publication = @program_check.unit_publication_at(checked, 0, 0).unwrap()
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(publication),
    ),
    4L,
  )
}

///|
test "standard check binds a cross join output guard" {
  let (_, _, environment, _, base) = public_input_fixture()
  let limits : @program_check.CheckLimits = {
    input: { ..base.input, max_stages: 1, },
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, stages: 1, steps: 10, },
    },
  }
  let source =
    #|{"version":"actql/0.1","id":"cross-guard","stages":[{"id":"crossed","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"left_raw"},{"from":"left_raw","distinct":["id"],"as":"left_rows"},{"values":{"schema":{"tag":{"type":"string","nullable":false}},"rows":[{"tag":"a"},{"tag":"b"}]},"as":"right_raw"},{"from":"right_raw","distinct":["tag"],"as":"right_rows"},{"from":"left_rows","cross_join":{"with":"right_rows","max_output_rows":2,"select":{"id":"left.id","tag":"right.tag"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","tag"]}}}],"results":{"out":{"from":{"stage":"crossed","result":"r"}}}}
  let checked = public_checked(
    @program_check.check_document(
      source,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  let closure = @context.stage_requirement_operations(
    @program_check.requirements(checked),
  )
  let mut found = false
  for index in 0..<@context.operation_closure_count(closure) {
    if @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(JoinOutputLimit(check))) {
      assert_eq(check.site.step, 4)
      assert_eq(@step_bounds.join_limit_effective_maximum(check.limit), 2L)
      assert_eq(@step_bounds.join_limit_guard_value(check.limit), Some(2L))
      found = true
    }
  }
  assert_true(found)
}
