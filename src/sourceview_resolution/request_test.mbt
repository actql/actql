///|
fn request_caps() -> RequestLimits {
  {
    max_work: 1000000,
    max_pairs: 10000,
    values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
  }
}

///|
fn request_slots(inputs : @inputs.Inputs) -> @slots.Slots {
  let owner = @inputs.source(inputs)
  let declared = @bindings.prepare(@stages.program(owner), {
    max_bindings: 100,
    max_work: 100000,
  }).unwrap()
  @slots.collect(owner, declared, { max_work: 1000000, max_slots: 10000, }).unwrap()
}

///|
fn check_request_fixture(
  wire : String,
  cid : String,
  input : String,
  declarations : String,
  expected : String,
) -> Unit raise {
  let inputs = fixture_inputs(input, declarations~)
  let resolved = resolve(inputs, fixture_catalog(wire, cid), caps()).unwrap()
  let slots = request_slots(inputs)
  let context = prepare_requests(resolved, slots, 1000000).unwrap()
  assert_true(physical_equal(request_context_source(context), resolved))
  assert_true(physical_equal(request_context_slots(context), slots))
  assert_true(
    prepare_requests(resolved, slots, request_context_work(context)) is Ok(_),
  )
  assert_true(
    prepare_requests(resolved, slots, request_context_work(context) - 1)
    is Err(e) &&
    e.kind == WorkLimit,
  )
  let foreign = fixture_inputs(input, declarations~)
  assert_true(
    prepare_requests(resolved, request_slots(foreign), 1000000) is Err(e) &&
    e.kind == ForeignSource,
  )
  let entry = at(resolved, 0).unwrap()
  let result = check_direct_request(context, entry, request_caps())
  let outcome = match result {
    Ok(_) => "accepted"
    Err(e) =>
      match e.kind {
        UnknownField(_) => "UnknownField"
        MissingField(_) => "MissingField"
        IncompatibleParameter(_) => "IncompatibleParameter"
        IncompatibleBinding(_) => "IncompatibleBinding"
        Literal(_) => "Literal"
        _ => "unexpected"
      }
  }
  assert_eq(outcome, expected)
  if result is Err(e) {
    assert_true(e.source is Some(_))
    if e.kind is UnknownField(name) {
      let path = @decode.cursor_path(e.source.unwrap())
      assert_eq(path[path.length() - 1], @source.Key(name))
      assert_true(@decode.cursor_key_span(e.source.unwrap()) is Some(_))
    }
    return
  }
  let checked = result.unwrap()
  assert_true(physical_equal(request_input(checked), entry))
  assert_true(physical_equal(request_context(checked), context))
  assert_eq(request_field_count(checked), @slots.count(slots))
  for i in 0..<request_field_count(checked) {
    let field = request_field_at(checked, i).unwrap()
    assert_true(physical_equal(field.slot, @slots.at(slots, i).unwrap()))
    match (field.value, field.slot.value) {
      (LiteralValue(v), @slots.Literal(_)) =>
        assert_true(physical_equal(v.contract, field.contract))
      (ParameterValue(v), @slots.Parameter(d)) =>
        assert_true(physical_equal(v, d))
      (BindingValue(v), @slots.Binding(d)) => assert_true(physical_equal(v, d))
      _ => fail("request role changed")
    }
  }
  let (work, pairs, nodes, text) = request_usage(checked)
  let exact : RequestLimits = {
    max_work: work,
    max_pairs: pairs,
    values: { max_nodes: nodes, max_depth: 100, max_text_bytes: text, },
  }
  assert_true(check_direct_request(context, entry, exact) is Ok(_))
  assert_true(
    check_direct_request(context, entry, { ..exact, max_work: work - 1, })
    is Err(e) &&
    e.kind == WorkLimit,
  )
  if pairs > 0 {
    assert_true(
      check_direct_request(context, entry, { ..exact, max_pairs: pairs - 1, })
      is Err(e) &&
      e.kind == PairLimit,
    )
  }
  if nodes > 0 {
    assert_true(
      check_direct_request(context, entry, {
        ..exact,
        values: { ..exact.values, max_nodes: nodes - 1, },
      })
      is Err(_),
    )
  }
  if text > 0 {
    assert_true(
      check_direct_request(context, entry, {
        ..exact,
        values: { ..exact.values, max_text_bytes: text - 1, },
      })
      is Err(_),
    )
  }
  let other = resolve(inputs, fixture_catalog(wire, cid), caps()).unwrap()
  assert_true(
    check_direct_request(context, at(other, 0).unwrap(), request_caps())
    is Err(e) &&
    e.kind == ForeignInput,
  )
}
