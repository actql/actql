///|
test "completed binding forwards exact originals without advancing pending or foreign inputs" {
  let definitions = declarations("{\"x\":{\"type\":\"number\"}}")
  let supplied = cursor("{\"x\":7}")
  let selected = Some(supplied)
  let caps = values_limit(nodes=100, depth=10, text=100)
  let original = @parameter_binding.prepare_binding_read(
    definitions, selected, caps,
  ).unwrap()
  assert_true(
    @parameter_binding.reuse_binding_read(original, definitions, selected, caps)
    is None,
  )
  assert_eq(@parameter_binding.binding_read_phase(original), BindingHeader)
  let completed = @parameter_binding.finish_binding_read(original).unwrap()
  let forwarded = @parameter_binding.reuse_binding_read(
      original,
      definitions,
      selected,
      values_limit(),
    )
    .unwrap()
    .unwrap()
  guard (completed, forwarded) is (Ready(a), Ready(b)) else {
    fail("expected original Ready")
  }
  assert_true(physical_equal(a, b))
  for
    (other_declarations, other_supplied, other_limits) in [
      (declarations("{\"x\":{\"type\":\"number\"}}"), selected, caps),
      (definitions, Some(cursor("{\"x\":7}")), caps),
      (definitions, Some(cursor("{\"x\":8}")), caps),
      (definitions, None, caps),
      (definitions, selected, { ..caps, max_nodes: 0, }),
    ] {
    assert_true(
      @parameter_binding.reuse_binding_read(
        original, other_declarations, other_supplied, other_limits,
      )
      is None,
    )
  }
}

///|
test "binding errors require exact limits and absent binding never aliases explicit NULL" {
  let definitions = declarations("{\"x\":{\"type\":\"number\",\"default\":7}}")
  let absent = @parameter_binding.prepare_binding_read(
    definitions,
    None,
    values_limit(),
  ).unwrap()
  assert_true(@parameter_binding.finish_binding_read(absent) is Ok(Ready(_)))
  let explicit_null = Some(cursor("{\"x\":null}"))
  assert_true(
    @parameter_binding.reuse_binding_read(
      absent,
      definitions,
      explicit_null,
      values_limit(),
    )
    is None,
  )
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    explicit_null,
    values_limit(nodes=0),
  ).unwrap()
  assert_true(@parameter_binding.finish_binding_read(original) is Err(_))
  assert_true(
    @parameter_binding.reuse_binding_read(
      original,
      definitions,
      explicit_null,
      values_limit(nodes=0),
    )
    is Some(Err(_)),
  )
  assert_true(
    @parameter_binding.reuse_binding_read(
      original,
      definitions,
      explicit_null,
      values_limit(),
    )
    is None,
  )
}

///|
test "completed binding narrows node and UTF8 ceilings only to actual successful work" {
  let definitions = declarations(
    "{\"left\":{\"type\":\"number\"},\"right\":{\"type\":\"string\"}}",
  )
  let supplied = Some(cursor("{\"left\":7,\"right\":\"😀\"}"))
  let caps = values_limit(nodes=100, depth=10, text=100)
  let original = @parameter_binding.prepare_binding_read(
    definitions, supplied, caps,
  ).unwrap()
  let completed = @parameter_binding.finish_binding_read(original).unwrap()
  // Two selected scalar nodes; parameter names4+5 and original UTF-8 value4.
  assert_eq(@parameter_binding.binding_usage(completed), (2, 13))
  let exact = { ..caps, max_nodes: 2, max_text_bytes: 13, }
  guard completed is Ready(values) &&
    @parameter_binding.reuse_binding_read(
      original, definitions, supplied, exact,
    )
    is Some(Ok(Ready(same))) else {
    fail("the measured complete original must fit its exact ceilings")
  }
  assert_true(physical_equal(values, same))
  assert_eq(
    identity_cid(values),
    identity_cid(ready_original_values(definitions, supplied, exact)),
  )
  for
    tighter in [
      { ..exact, max_nodes: 1, },
      { ..exact, max_text_bytes: 12, },
      { ..exact, max_depth: 9, },
      { ..exact, max_nodes: -1, },
    ] {
    assert_true(
      @parameter_binding.reuse_binding_read(
        original, definitions, supplied, tighter,
      )
      is None,
    )
  }
  assert_true(
    @parameter_binding.bind(definitions, supplied, { ..exact, max_nodes: 1, })
    is Err(_),
  )
  assert_true(
    @parameter_binding.bind(definitions, supplied, {
      ..exact,
      max_text_bytes: 12,
    })
    is Err(_),
  )
}

///|
fn ready_original_values(
  definitions : @parameter_binding.Declarations,
  supplied : @decode.Cursor?,
  caps : @value.Limits,
) -> @parameter_binding.BoundValues {
  guard @parameter_binding.bind(definitions, supplied, caps)
    is Ok(Ready(values)) else {
    abort("independent original binding did not complete")
  }
  values
}

///|
test "measured binding reuse keeps selected defaults missing declarations and exact error ceilings" {
  let definitions = declarations(
    "{\"a\":{\"type\":\"string\",\"default\":\"old\"},\"b\":{\"type\":\"number\"},\"c\":{\"type\":\"number\"}}",
  )
  let supplied = Some(cursor("{\"b\":7}"))
  let caps = values_limit(nodes=100, depth=10, text=100)
  let original = @parameter_binding.prepare_binding_read(
    definitions, supplied, caps,
  ).unwrap()
  let completed = @parameter_binding.finish_binding_read(original).unwrap()
  assert_eq(@parameter_binding.binding_usage(completed), (2, 5))
  guard completed is NeedsBindings(missing) &&
    @parameter_binding.reuse_binding_read(original, definitions, supplied, {
      ..caps,
      max_nodes: 2,
      max_text_bytes: 5,
    })
    is Some(Ok(NeedsBindings(same))) else {
    fail("missing values must remain missing under fitting ceilings")
  }
  assert_true(physical_equal(missing, same))
  assert_eq(@parameter_binding.missing_names(same), ["c"])
  let invalid = Some(cursor("{\"b\":\"wrong\"}"))
  let failed = @parameter_binding.prepare_binding_read(
    definitions, invalid, caps,
  ).unwrap()
  assert_true(@parameter_binding.finish_binding_read(failed) is Err(_))
  assert_true(
    @parameter_binding.reuse_binding_read(failed, definitions, invalid, caps)
    is Some(Err(_)),
  )
  assert_true(
    @parameter_binding.reuse_binding_read(failed, definitions, invalid, {
      ..caps,
      max_nodes: 99,
    })
    is None,
  )
}
