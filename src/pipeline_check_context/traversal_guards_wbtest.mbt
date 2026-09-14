///|
test "traversal guards retain authored restrictions without replacing candidate claims" {
  for emission in ["nodes", "paths"] {
    for value in [1, 7, 20] {
      let (pipeline, limits) = traversal_checked_fixture(
        emission,
        guard_text=",\"max_output_rows\":" + value.to_string(),
      )
      let bound = @step_bounds.traversal_limit_guards(limits).unwrap()
      let index = @step_bounds.traversal_limit_guard_index(limits).unwrap()
      let occurrence = @pipeline.author_guard_at(
        @pipeline.bound_guard_occurrences(bound),
        index,
      ).unwrap()
      assert_true(
        physical_equal(@pipeline.author_guard_pipeline(occurrence), pipeline),
      )
      assert_eq(@pipeline.author_guard_step(occurrence), 2)
      assert_eq(
        @pipeline.author_guard_scope(occurrence),
        @pipeline.TraverseOutputRows,
      )
      assert_eq(
        @step_bounds.traversal_limit_guard_value(limits),
        Some(value.to_int64()),
      )
      assert_eq(
        @step_bounds.traversal_limit_effective_maximum(limits, SearchPaths),
        7L,
      )
      assert_eq(
        @step_bounds.traversal_limit_effective_maximum(limits, OutputRows),
        value.min(7).to_int64(),
      )
      assert_eq(
        @derivation.minimum_value(
          @wire.limit_minimum(
            @step_bounds.traversal_limit_claim(limits, OutputRows),
          ),
        ),
        7L,
      )
      let check = fn(guards, work) {
        @step_bounds.check_traversal_limits(
          pipeline,
          2,
          @step_bounds.traversal_limit_sources(limits),
          @step_bounds.traversal_limit_program(limits),
          @step_bounds.traversal_limit_policy(limits),
          0,
          1,
          guards~,
          max_work=work,
        )
      }
      let work = @step_bounds.traversal_limit_work(limits)
      assert_true(check(Some(bound), work) is Ok(_))
      assert_true(check(Some(bound), work - 1) is Err(_))
      assert_true(check(None, work) is Err(UnresolvedAuthorSource))
      let (_, foreign) = traversal_checked_fixture(
        emission,
        guard_text=",\"max_output_rows\":" + value.to_string(),
      )
      assert_true(
        check(@step_bounds.traversal_limit_guards(foreign), work)
        is Err(ForeignGuardOwner),
      )
    }
  }
}

///|
test "traversal collection checks exact Parameter bindings rather than equal guard values" {
  let declarations = @parameter.read_declarations(
    Some(asof_test_cursor("{\"n\":{\"type\":\"number\",\"default\":2}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let bind = fn() {
    guard @parameter.bind(declarations, None, {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      }).unwrap()
      is @parameter.Ready(values) else {
      abort("fixture binding")
    }
    values
  }
  let values = bind()
  let (pipeline, limits) = traversal_checked_fixture(
    "paths",
    guard_text=",\"max_output_rows\":{\"$param\":\"n\"}",
    parameters=Some(declarations),
    bindings=Some(values),
  )
  let bound = @step_bounds.traversal_limit_guards(limits).unwrap()
  let applications = @step_bounds.check_traversal_complete(
    pipeline,
    @step_bounds.traversal_limit_sources(limits),
    @step_bounds.traversal_limit_program(limits),
    @step_bounds.traversal_limit_policy(limits),
    [limits],
    max_work=100,
  ).unwrap()
  assert_eq(@step_bounds.traversal_limit_guard_value(limits), Some(2L))
  for (binding, expected) in [(values, true), (bind(), false)] {
    let repeated = @pipeline.bind_author_guards(
      @pipeline.collect_author_guards(
        pipeline,
        max_work=100,
        max_text_bytes=1000,
      ).unwrap(),
      Some(binding),
      max_work=100,
      max_text_bytes=1000,
    ).unwrap()
    assert_eq(
      @step_bounds.traversal_application_guard_bindings_match(
        applications, repeated,
      ),
      expected,
    )
  }
  assert_true(
    @step_bounds.traversal_application_guard_bindings_match(applications, bound),
  )
  let (_, foreign) = traversal_checked_fixture(
    "paths",
    guard_text=",\"max_output_rows\":2",
  )
  assert_false(
    @step_bounds.traversal_application_guard_bindings_match(
      applications,
      @step_bounds.traversal_limit_guards(foreign).unwrap(),
    ),
  )
}
