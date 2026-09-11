///|
fn guard_declarations() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"nullable\":true,\"default\":7},\"unused\":{\"type\":\"string\",\"default\":\"text\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn guard_occurrences(
  d : @parameter.Declarations,
) -> @pipeline_typing.AuthorGuards {
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"join":{"with":"r","kind":"semi","on":"id","max_output_rows":7},"from":"l"},
        #| {"join":{"with":"r","kind":"semi","on":"id","max_output_rows":{"$param":"cap"}},"from":"l"}]
      ),
    ),
    [("l", schema()), ("r", schema())],
    Some(d),
    None,
    limits(),
  ).unwrap()
  @pipeline_typing.collect_author_guards(p, max_work=100, max_text_bytes=1000).unwrap()
}

///|
fn guard_bindings(
  d : @parameter.Declarations,
  supplied : String?,
) -> @parameter.BoundValues raise {
  let result = @parameter.bind(d, supplied.map(cursor), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  guard result is Ready(values) else { fail("ready expected") }
  values
}

///|
test "guard binding retains the declaration owner and default provenance" {
  let d = guard_declarations()
  let occurrences = guard_occurrences(d)
  let values = guard_bindings(d, None)
  assert_true(physical_equal(@parameter.bound_declarations(values), d))
  assert_eq(@parameter.bound_value_count(values), 2)
  assert_true(@parameter.bound_value_at(values, 0).unwrap().origin is Default)
  assert_true(@parameter.bound_value_at(values, -1) is None)
  assert_true(@parameter.bound_value_at(values, 2) is None)
  let bound = @pipeline_typing.bind_author_guards(
    occurrences,
    Some(values),
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.bound_guard_value_at(bound, 0), Some(7L))
  assert_eq(@pipeline_typing.bound_guard_value_at(bound, 1), Some(7L))
  assert_true(@pipeline_typing.bound_guard_value_at(bound, 2) is None)
  assert_true(
    physical_equal(@pipeline_typing.bound_guard_occurrences(bound), occurrences),
  )
  assert_true(
    physical_equal(
      @pipeline_typing.bound_guard_bindings(bound).unwrap(),
      values,
    ),
  )
  let supplied = guard_bindings(d, Some("{\"cap\":9007199254740991}"))
  let explicit = @pipeline_typing.bind_author_guards(
    occurrences,
    Some(supplied),
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(
    @pipeline_typing.bound_guard_value_at(explicit, 1),
    Some(9007199254740991L),
  )
  assert_eq(@pipeline_typing.bound_guard_value_at(bound, 1), Some(7L))
  let (work, text) = @pipeline_typing.bound_guard_usage(bound)
  assert_true(
    @pipeline_typing.bind_author_guards(
      occurrences,
      Some(values),
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.bind_author_guards(
      occurrences,
      Some(values),
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.bind_author_guards(
      occurrences,
      Some(values),
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.bind_author_guards(
      occurrences,
      Some(values),
      max_work=-1,
      max_text_bytes=text,
    )
    is Err({ kind: InvalidLimits, .. }),
  )
}

///|
test "guard bindings reject invalid values and report the exact occurrence" {
  let d = guard_declarations()
  let occurrences = guard_occurrences(d)
  for text in ["0", "-1", "1.5", "9007199254740992", "null"] {
    let values = guard_bindings(d, Some("{\"cap\":" + text + "}"))
    let error = @pipeline_typing.bind_author_guards(
      occurrences,
      Some(values),
      max_work=100,
      max_text_bytes=1000,
    ).unwrap_err()
    assert_eq(error.kind, InvalidGuardValue("cap"))
    assert_eq(error.path, [Index(1), Key("join"), Key("max_output_rows")])
    assert_eq(
      error.span,
      @decode.cursor_span(
        @pipeline_typing.author_guard_source(
          @pipeline_typing.author_guard_at(occurrences, 1).unwrap(),
        ),
      ),
    )
  }
  let missing = @pipeline_typing.bind_author_guards(
    occurrences,
    None,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap_err()
  assert_eq(missing.kind, MissingGuardBinding("cap"))
  assert_eq(missing.path, [Index(1), Key("join"), Key("max_output_rows")])
  let other = guard_bindings(guard_declarations(), None)
  assert_true(
    @pipeline_typing.bind_author_guards(
      occurrences,
      Some(other),
      max_work=100,
      max_text_bytes=1000,
    )
    is Err({ kind: GuardBindingOwnerMismatch, .. }),
  )
}

///|
test "literal guards need no binding but unrelated bindings are not accepted" {
  let p = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\",\"max_output_rows\":1}}]",
  ).unwrap()
  let occurrences = @pipeline_typing.collect_author_guards(
    p,
    max_work=10,
    max_text_bytes=100,
  ).unwrap()
  let bound = @pipeline_typing.bind_author_guards(
    occurrences,
    None,
    max_work=1,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.bound_guard_value_at(bound, 0), Some(1L))
  assert_true(@pipeline_typing.bound_guard_bindings(bound) is None)
  assert_true(
    @pipeline_typing.bind_author_guards(
      occurrences,
      Some(guard_bindings(guard_declarations(), None)),
      max_work=100,
      max_text_bytes=1000,
    )
    is Err({ kind: GuardBindingOwnerMismatch, .. }),
  )
}
