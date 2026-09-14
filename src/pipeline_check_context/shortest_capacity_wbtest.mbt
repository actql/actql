///|
test "shortest capacity retains dedicated subjects guard scope and independent path ceiling" {
  for value in [1, 7, 20] {
    let (pipeline, limits) = traversal_checked_fixture(
      "paths",
      shortest=true,
      guard_text=",\"max_output_rows\":" + value.to_string(),
    )
    assert_true(
      @pipeline.step_at(pipeline, 2).unwrap().operation
      is @pipeline.Shortest(..),
    )
    let guards = @step_bounds.traversal_limit_guards(limits).unwrap()
    let occurrence = @pipeline.author_guard_at(
      @pipeline.bound_guard_occurrences(guards),
      @step_bounds.traversal_limit_guard_index(limits).unwrap(),
    ).unwrap()
    assert_eq(
      @pipeline.author_guard_scope(occurrence),
      @pipeline.ShortestOutputRows,
    )
    assert_eq(@pipeline.author_guard_step(occurrence), 2)
    assert_true(
      physical_equal(@pipeline.author_guard_pipeline(occurrence), pipeline),
    )
    assert_eq(
      @step_bounds.traversal_limit_guard_value(limits),
      Some(value.to_int64()),
    )
    for
      (scope, suffix, maximum) in [
        (@step_bounds.SearchPaths, ":paths", 7),
        (@step_bounds.OutputRows, "", value.min(7)),
      ] {
      assert_eq(
        @wire.limit_subject(@step_bounds.traversal_limit_claim(limits, scope)),
        "shortest_path:checked-step:2" + suffix,
      )
      assert_eq(
        @step_bounds.traversal_limit_effective_maximum(limits, scope),
        maximum.to_int64(),
      )
    }
    let check = fn(bound, work) {
      @step_bounds.check_traversal_limits(
        pipeline,
        2,
        @step_bounds.traversal_limit_sources(limits),
        @step_bounds.traversal_limit_program(limits),
        @step_bounds.traversal_limit_policy(limits),
        0,
        1,
        guards=bound,
        max_work=work,
      )
    }
    // Two candidate passes each inspect two claim slots and one candidate;
    // the original guard occurrence is charged once, independently of the value.
    assert_eq(@step_bounds.traversal_limit_work(limits), 7)
    assert_true(check(Some(guards), 7) is Ok(_))
    assert_true(check(Some(guards), 6) is Err(_))
    assert_true(check(None, 7) is Err(UnresolvedAuthorSource))
    let (_, foreign) = traversal_checked_fixture(
      "paths",
      shortest=true,
      guard_text=",\"max_output_rows\":" + value.to_string(),
    )
    assert_true(
      check(@step_bounds.traversal_limit_guards(foreign), 7)
      is Err(ForeignGuardOwner),
    )
    let applications = @step_bounds.check_traversal_complete(
      pipeline,
      @step_bounds.traversal_limit_sources(limits),
      @step_bounds.traversal_limit_program(limits),
      @step_bounds.traversal_limit_policy(limits),
      [limits],
      max_work=100,
    ).unwrap()
    assert_true(
      physical_equal(
        @step_bounds.traversal_application_at(applications, 2).unwrap(),
        limits,
      ),
    )
    assert_true(
      @step_bounds.check_traversal_applications(
        pipeline,
        @step_bounds.traversal_limit_sources(limits),
        @step_bounds.traversal_limit_program(limits),
        @step_bounds.traversal_limit_policy(limits),
        [],
        max_work=100,
      )
      is Err(MissingApplication(2)),
    )
  }
}
