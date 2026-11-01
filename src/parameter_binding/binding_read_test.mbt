///|
test "staged binding retains original selection preflight and cached default without another Value admission" {
  let definitions = declarations(
    "{\"z\":{\"type\":\"int64\",\"default\":\"9007199254740993\"},\"a\":{\"type\":\"number\"}}",
  )
  let supplied = cursor("{\"a\":2}")
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    Some(supplied),
    values_limit(),
  ).unwrap()
  assert_eq(
    @parameter_binding.binding_read_phase(original),
    @parameter_binding.BindingHeader,
  )
  assert_true(@parameter_binding.binding_read_pending_source(original) is None)
  @parameter_binding.advance_binding_read(original)
  assert_eq(
    @parameter_binding.binding_read_phase(original),
    @parameter_binding.BindingSelection,
  )
  @parameter_binding.advance_binding_read(original)
  let selected = @parameter_binding.binding_read_pending_source(original)
  let declaration = @parameter_binding.binding_read_pending_declaration(
    original,
  )
  assert_true(
    physical_equal(
      declaration.unwrap(),
      @parameter_binding.declaration_at(definitions, 0).unwrap(),
    ),
  )
  assert_true(
    @parameter_binding.binding_read_origin(original)
    is @parameter_binding.Supplied,
  )
  assert_true(
    physical_equal(
      selected,
      @parameter_binding.binding_read_pending_source(original),
    ),
  )
  assert_true(
    physical_equal(
      declaration,
      @parameter_binding.binding_read_pending_declaration(original),
    ),
  )
  assert_eq(@decode.cursor_path(selected.unwrap()), [@source.Key("a")])
  @parameter_binding.advance_binding_read(original)
  assert_eq(
    @parameter_binding.binding_read_phase(original),
    @parameter_binding.BindingValue,
  )
  assert_true(
    physical_equal(
      selected,
      @parameter_binding.binding_read_pending_source(original),
    ),
  )
  @parameter_binding.advance_binding_read(original)
  assert_eq(
    @parameter_binding.binding_read_phase(original),
    @parameter_binding.BindingSelection,
  )
  assert_true(@parameter_binding.binding_read_pending_source(original) is None)
  @parameter_binding.advance_binding_read(original)
  assert_true(
    @parameter_binding.binding_read_origin(original)
    is @parameter_binding.Default,
  )
  assert_eq(
    @decode.cursor_path(
      @parameter_binding.binding_read_pending_source(original).unwrap(),
    ),
    [@source.Key("z"), @source.Key("default")],
  )
  let result = @parameter_binding.finish_binding_read(original)
  assert_true(
    physical_equal(result, @parameter_binding.finish_binding_read(original)),
  )
  @parameter_binding.advance_binding_read(original)
  assert_true(
    physical_equal(result, @parameter_binding.finish_binding_read(original)),
  )
  guard result.unwrap() is @parameter_binding.Ready(values) else {
    fail("original completed binding")
  }
  assert_true(
    physical_equal(@parameter_binding.bound_declarations(values), definitions),
  )
  assert_eq(@parameter_binding.bound_value_count(values), 2)
  let again = original_default_values(definitions, Some("{\"a\":2}"))
  assert_true(
    physical_equal(
      @parameter_binding.bound_value_at(values, 1).unwrap().value,
      @parameter_binding.bound_value_at(again, 1).unwrap().value,
    ),
  )
  assert_eq(identity_cid(values), identity_cid(again))
  assert_true(@parameter_binding.binding_read_pending_source(original) is None)
}

///|
test "staged binding never lets missing entries mask supplied refusal or change failure origin" {
  let definitions = declarations(
    "{\"a\":{\"type\":\"number\"},\"z\":{\"type\":\"number\",\"integer\":true}}",
  )
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    Some(cursor("{\"z\":1.5}")),
    values_limit(),
  ).unwrap()
  @parameter_binding.advance_binding_read(original)
  @parameter_binding.advance_binding_read(original)
  assert_eq(
    @parameter_binding.binding_read_phase(original),
    @parameter_binding.BindingSelection,
  )
  @parameter_binding.advance_binding_read(original)
  assert_true(
    @parameter_binding.binding_read_origin(original)
    is @parameter_binding.Supplied,
  )
  let result = @parameter_binding.finish_binding_read(original)
  assert_true(
    result
    is Err(
      @parameter_binding.BindingInput(
        @parameter_binding.Supplied,
        @parameter_binding.ParameterIssue(
          @parameter_binding.NumericConstraint,
          ..
        )
      )
    ),
  )
  assert_true(
    physical_equal(result, @parameter_binding.finish_binding_read(original)),
  )
  let defaults = declarations(
    "{\"x\":{\"type\":\"string\",\"default\":\"long\"}}",
  )
  let original = @parameter_binding.prepare_binding_read(
    defaults,
    None,
    values_limit(text=1),
  ).unwrap()
  let result = @parameter_binding.finish_binding_read(original)
  guard result
    is Err(
      @parameter_binding.BindingInput(
        @parameter_binding.Default,
        @parameter_binding.ParameterIssue(kind, path~, span~)
      )
    ) else {
    fail("original selected default budget refusal")
  }
  assert_eq(kind, @parameter_binding.BudgetExceeded)
  assert_eq(path, [@source.Key("x"), @source.Key("default")])
  let default_source = @decode.field_at(
      @parameter_binding.declaration_source(
        @parameter_binding.declaration_at(defaults, 0).unwrap(),
      ),
      1,
    ).unwrap().1
  assert_eq(span, @decode.cursor_span(default_source))
}

///|
test "binding Header preserves closed supplied shape empty and invalid limits before selection" {
  let empty = @parameter_binding.read_declarations(None, limits()).unwrap()
  for supplied in [None, Some(cursor("{}"))] {
    let original = @parameter_binding.prepare_binding_read(
      empty,
      supplied,
      values_limit(),
    ).unwrap()
    @parameter_binding.advance_binding_read(original)
    assert_eq(
      @parameter_binding.binding_read_phase(original),
      @parameter_binding.BindingComplete,
    )
    let result = @parameter_binding.finish_binding_read(original)
    guard result.unwrap() is @parameter_binding.Ready(values) else {
      fail("original empty bindings")
    }
    assert_eq(@parameter_binding.bound_value_count(values), 0)
    assert_eq(@parameter_binding.binding_usage(result.unwrap()), (0, 0))
  }
  let original = @parameter_binding.prepare_binding_read(
    empty,
    Some(cursor("{\"extra\":1}")),
    values_limit(),
  ).unwrap()
  let result = @parameter_binding.finish_binding_read(original)
  assert_true(
    result
    is Err(
      @parameter_binding.BindingInput(
        @parameter_binding.Supplied,
        @parameter_binding.Decode({ kind: @decode.UnknownField, .. })
      )
    ),
  )
  assert_true(
    @parameter_binding.prepare_binding_read(empty, None, values_limit(nodes=-1))
    is Err(@parameter_binding.InvalidLimits),
  )
}

///|
test "staged binding keeps explicit NULL supplied and reports missing originals without partial BoundValues" {
  let definitions = declarations(
    "{\"a\":{\"type\":\"string\",\"nullable\":true,\"default\":\"fallback\"},\"z\":{\"type\":\"number\"}}",
  )
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    Some(cursor("{\"a\":null}")),
    values_limit(),
  ).unwrap()
  let result = @parameter_binding.finish_binding_read(original)
  guard result.unwrap() is @parameter_binding.NeedsBindings(missing) else {
    fail("original missing declaration")
  }
  assert_eq(@parameter_binding.missing_count(missing), 1)
  assert_true(
    physical_equal(
      @parameter_binding.missing_at(missing, 0).unwrap(),
      @parameter_binding.declaration_at(definitions, 1).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      @parameter_binding.missing_declaration_owner(missing),
      definitions,
    ),
  )
  assert_eq(@parameter_binding.binding_usage(result.unwrap()), (1, 1))
  let selected = original_default_values(
    declarations(
      "{\"a\":{\"type\":\"string\",\"nullable\":true,\"default\":\"fallback\"}}",
    ),
    Some("{\"a\":null}"),
  )
  assert_true(
    @parameter_binding.bound_value_at(selected, 0).unwrap().origin
    is @parameter_binding.Supplied,
  )
  assert_true(
    @parameter_binding.bound_value_at(selected, 0).unwrap().value.value
    is @value.Null,
  )
}
