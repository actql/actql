///|
fn declarations() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(cursor("{\"amount\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn prepared_with(d : @parameter.Declarations) -> @lowering_relation.Prepared {
  @lowering_relation.prepare(
    @pipeline.check(
      cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":{\"$param\":\"amount\"}}]},\"as\":\"seed\"}]",
      ),
      [],
      Some(d),
      None,
      {
        max_steps: 100,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap(),
    limits(),
  ).unwrap()
}

///|
fn bound(d : @parameter.Declarations) -> @parameter.BoundValues {
  match
    @parameter.bind(d, Some(cursor("{\"amount\":7}")), {
      max_nodes: 100,
      max_depth: 20,
      max_text_bytes: 1000,
    }).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("fixture is complete")
  }
}

///|
test "parameter bindings retain exact checked ownership and admitted values" {
  let d = declarations()
  let p = prepared_with(d)
  let bindings = bound(d)
  let ready = @lowering_relation.bind_parameters(
    p,
    Some(bindings),
    max_parameters=1,
    max_name_bytes=6,
  ).unwrap()
  assert_true(physical_equal(@lowering_relation.bound_preparation(ready), p))
  assert_true(
    physical_equal(
      @lowering_relation.parameter_bindings(ready).unwrap(),
      bindings,
    ),
  )
  assert_true(
    @lowering_relation.parameter_value(ready, "amount").unwrap().value
    is @value.Number(7.0),
  )
  assert_true(@lowering_relation.parameter_value(ready, "absent") is None)
  // Same spelling, type and values do not make a separately checked owner ours.
  guard @lowering_relation.bind_parameters(
      p,
      Some(bound(declarations())),
      max_parameters=1,
      max_name_bytes=6,
    )
    is Err(issue) else {
    fail("foreign owner admitted")
  }
  assert_eq(issue.kind, @lowering_relation.BindingOwnerMismatch)
}

///|
test "missing and extraneous parameter environments are distinct failures" {
  let d = declarations()
  guard @lowering_relation.bind_parameters(
      prepared_with(d),
      None,
      max_parameters=10,
      max_name_bytes=100,
    )
    is Err(missing) else {
    fail("missing bindings admitted")
  }
  assert_eq(missing.kind, @lowering_relation.MissingBindings)
  let empty = @lowering_relation.prepare(checked(""), limits()).unwrap()
  assert_true(
    @lowering_relation.bind_parameters(
      empty,
      None,
      max_parameters=0,
      max_name_bytes=0,
    )
    is Ok(_),
  )
  guard @lowering_relation.bind_parameters(
      empty,
      Some(bound(d)),
      max_parameters=10,
      max_name_bytes=100,
    )
    is Err(foreign) else {
    fail("extraneous environment admitted")
  }
  assert_eq(foreign.kind, @lowering_relation.BindingOwnerMismatch)
}

///|
test "parameter indexing has exact count and text boundaries" {
  let d = declarations()
  let p = prepared_with(d)
  let b = Some(bound(d))
  for (count, bytes) in [(0, 6), (1, 5)] {
    guard @lowering_relation.bind_parameters(
        p,
        b,
        max_parameters=count,
        max_name_bytes=bytes,
      )
      is Err(issue) else {
      fail("binding budget exceeded silently")
    }
    assert_eq(issue.kind, @lowering_relation.BindingBudgetExceeded)
  }
  guard @lowering_relation.bind_parameters(
      p,
      b,
      max_parameters=-1,
      max_name_bytes=6,
    )
    is Err(issue) else {
    fail("negative budget admitted")
  }
  assert_eq(issue.kind, @lowering_relation.InvalidBindingLimits)
}
