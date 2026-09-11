///|
fn parameter_guard_closure(
  d : @parameter.Declarations,
) -> @pipeline_typing.ContextualClosure {
  let p = @pipeline_typing.author_guards_pipeline(guard_occurrences(d))
  let input = @pipeline_typing.produced_input(p, Step(1)).unwrap()
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
  @pipeline_typing.resolve_contextual_closure(
    root,
    max_steps=4,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
}

///|
test "producer guard binding retains visits and shares exact budgets" {
  let d = guard_declarations()
  let closure = parameter_guard_closure(d)
  let defaults = guard_bindings(d, None)
  let supplied = guard_bindings(d, Some("{\"cap\":9}"))
  let bindings = [None, Some(defaults), Some(supplied)]
  let bound = @pipeline_typing.bind_contextual_guards(
    closure,
    bindings,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  assert_true(
    physical_equal(@pipeline_typing.bound_guard_closure_source(bound), closure),
  )
  for i in 0..<3 {
    let entry = @pipeline_typing.bound_guard_closure_at(bound, i).unwrap()
    assert_true(
      physical_equal(
        @pipeline_typing.bound_guard_occurrences(entry),
        @pipeline_typing.contextual_closure_guards_at(closure, i).unwrap(),
      ),
    )
  }
  assert_eq(
    @pipeline_typing.bound_guard_value_at(
      @pipeline_typing.bound_guard_closure_at(bound, 1).unwrap(),
      1,
    ),
    Some(7L),
  )
  assert_eq(
    @pipeline_typing.bound_guard_value_at(
      @pipeline_typing.bound_guard_closure_at(bound, 2).unwrap(),
      1,
    ),
    Some(9L),
  )
  assert_true(@pipeline_typing.bound_guard_closure_at(bound, -1) is None)
  assert_true(@pipeline_typing.bound_guard_closure_at(bound, 3) is None)
  let (work, text) = @pipeline_typing.bound_guard_closure_usage(bound)
  assert_eq(work, 11) // Three visits; two bound entries and two guards per producer.
  assert_eq(text, 24) // "cap" + "unused" catalog names, plus the guard lookup, twice.
  assert_true(
    @pipeline_typing.bind_contextual_guards(
      closure,
      bindings,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.bind_contextual_guards(
      closure,
      bindings,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.bind_contextual_guards(
      closure,
      bindings,
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
  bindings[2] = None
  assert_true(
    physical_equal(
      @pipeline_typing.bound_guard_bindings(
        @pipeline_typing.bound_guard_closure_at(bound, 2).unwrap(),
      ).unwrap(),
      supplied,
    ),
  )
}

///|
test "producer guard binding rejects later invalid or foreign bindings atomically" {
  let d = guard_declarations()
  let closure = parameter_guard_closure(d)
  let valid = guard_bindings(d, None)
  let producer = @pipeline_typing.contextual_orders_pipeline(
    @pipeline_typing.contextual_closure_at(closure, 2).unwrap(),
  )
  for
    (bad, expected) in [
      (None, @pipeline_typing.MissingGuardBinding("cap")),
      (
        Some(guard_bindings(d, Some("{\"cap\":0}"))),
        @pipeline_typing.InvalidGuardValue("cap"),
      ),
      (
        Some(guard_bindings(guard_declarations(), None)),
        @pipeline_typing.GuardBindingOwnerMismatch,
      ),
    ] {
    let error = @pipeline_typing.bind_contextual_guards(
      closure,
      [None, Some(valid), bad],
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap_err()
    assert_true(physical_equal(error.pipeline, producer))
    assert_eq(error.issue.kind, expected)
    if expected != @pipeline_typing.GuardBindingOwnerMismatch {
      assert_eq(error.issue.path, [
        Index(1),
        Key("join"),
        Key("max_output_rows"),
      ])
    }
  }
  for entries in [[], [None], [None, None, None, None]] {
    let error = @pipeline_typing.bind_contextual_guards(
      closure,
      entries,
      max_work=1000,
      max_text_bytes=1000,
    ).unwrap_err()
    assert_eq(error.issue.kind, GuardBindingCountMismatch)
  }
  for (work, text) in [(-1, 100), (100, -1)] {
    let error = @pipeline_typing.bind_contextual_guards(
      closure,
      [None, Some(valid), Some(valid)],
      max_work=work,
      max_text_bytes=text,
    ).unwrap_err()
    assert_eq(error.issue.kind, InvalidLimits)
  }
}
