///|
test "formal check closes sort and take through an imported Result" {
  for
    steps in [
      "[{\"sort\":[],\"as\":\"ordered\"}]", "[{\"sort\":[{\"value\":\"desc\"}],\"as\":\"ordered\"}]",
      "[{\"sort\":[{\"value\":\"desc\"}]},{\"take\":1,\"as\":\"ordered\"}]", "[{\"take\":1,\"as\":\"ordered\"}]",
    ] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      second_steps=steps,
      second_result_from="ordered",
      extra_step_budget=2,
    )
    assert_eq(checked.length(), 1)
    let program = checked[0]
    assert_eq(unit_count(program), 2)
    let pipeline = unit_pipeline(program, 1).unwrap()
    let publication = unit_publication_at(program, 1, 0).unwrap()
    let target = @pipeline.lookup(pipeline, "ordered").unwrap()
    assert_true(target is @pipeline.Step(_))
    let selected = @context.publication_row_limit_result(
      publication_selection(publication),
    )
    assert_eq(
      @pipeline.publication_target(@publication.port_publication(selected.port)),
      target,
    )
    let operations = @context.stage_requirement_operations(
      requirements(program),
    )
    let mut orders = 0
    for i in 0..<@context.operation_closure_count(operations) {
      if @context.operation_closure_at(operations, i)
        is Some(StaticResolution(Order(link))) &&
        link.site.stage == 1 {
        assert_true(physical_equal(link.site.pipeline, pipeline))
        assert_true(link.site.step < @pipeline.step_count(pipeline))
        orders += 1
      }
    }
    if steps != "[{\"sort\":[],\"as\":\"ordered\"}]" {
      assert_true(orders > 0)
    }
  }
}

///|
test "invalid take in a later Stage returns no partial CheckedProgram" {
  let checked : Array[CheckedProgram] = []
  try {
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      second_steps="[{\"take\":0,\"as\":\"ordered\"}]",
      second_result_from="ordered",
    )
    fail("zero take returned a successful Program")
  } catch {
    LocalConstructionFailure::Source(
      SourceFailure::SourceView(
        @context.SourceViewContextIssue::Program(
          @context.SourceViewProgramIssue::Program(
            @results.LocalProgramIssue::Pipeline(_, issue)
          )
        )
      )
    ) => assert_true(issue.kind is @pipeline.Operation(_))
    e => raise e
  }
  assert_eq(checked.length(), 0)
}
