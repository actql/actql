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
