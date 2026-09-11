///|
test "producer closure retains guards from unused branches and repeated inputs" {
  let base = @pipeline_typing.check(
    cursor(
      "[{\"join\":{\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\",\"max_output_rows\":7},\"from\":\"l\",\"as\":\"unused\"}," +
      count_values(1, "good") +
      "]",
    ),
    [("l", schema()), ("r", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let input = @pipeline_typing.produced_input(base, Step(1)).unwrap()
  let root = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [
      ("a", @pipeline_typing.ProducedInput(input)),
      ("b", @pipeline_typing.ProducedInput(input)),
    ],
    None,
    Some(cursor("\"a\"")),
    limits(),
  ).unwrap()
  let closure = @pipeline_typing.resolve_contextual_closure(
    root,
    max_steps=4,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_closure_count(closure), 3)
  assert_eq(
    @pipeline_typing.author_guard_count(
      @pipeline_typing.contextual_closure_guards_at(closure, 0).unwrap(),
    ),
    0,
  )
  for i in [1, 2] {
    let guards = @pipeline_typing.contextual_closure_guards_at(closure, i).unwrap()
    assert_eq(@pipeline_typing.author_guard_count(guards), 1)
    let occurrence = @pipeline_typing.author_guard_at(guards, 0).unwrap()
    assert_true(
      physical_equal(@pipeline_typing.author_guard_pipeline(occurrence), base),
    )
    assert_eq(@pipeline_typing.author_guard_step(occurrence), 0)
    assert_true(
      @pipeline_typing.author_guard_value(occurrence) is @relation.Literal(7L),
    )
    assert_eq(
      @decode.cursor_path(@pipeline_typing.author_guard_source(occurrence)),
      [Index(0), Key("join"), Key("max_output_rows")],
    )
    assert_true(
      physical_equal(
        @pipeline_typing.contextual_orders_pipeline(
          @pipeline_typing.contextual_closure_at(closure, i).unwrap(),
        ),
        @pipeline_typing.author_guards_pipeline(guards),
      ),
    )
  }
  assert_true(
    @pipeline_typing.contextual_closure_guards_at(closure, -1) is None,
  )
  assert_true(@pipeline_typing.contextual_closure_guards_at(closure, 3) is None)
  let (work, text) = @pipeline_typing.contextual_closure_usage(closure)
  assert_eq(text, 30)
  assert_true(
    @pipeline_typing.resolve_contextual_closure(
      root,
      max_steps=4,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  let error = @pipeline_typing.resolve_contextual_closure(
    root,
    max_steps=4,
    max_work=work,
    max_text_bytes=text - 1,
  ).unwrap_err()
  assert_true(physical_equal(error.pipeline, base))
  assert_eq(error.issue.kind, BudgetExceeded)
  assert_eq(error.issue.path, [Index(0), Key("join")])
  assert_true(
    @pipeline_typing.resolve_contextual_closure(
      root,
      max_steps=4,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
}
