///|
fn check_keyed_request_fixture(
  wire : String,
  cid : String,
  input : String,
  declarations : String,
  expected : String,
) -> Unit raise {
  let source_inputs = fixture_inputs(input, declarations~)
  let catalog = fixture_catalog(wire, cid)
  let resolved = resolve(source_inputs, catalog, caps()).unwrap()
  let context = prepare_requests(
    resolved,
    request_slots(source_inputs),
    1000000,
  ).unwrap()
  let entry = at(resolved, 0).unwrap()
  let result = check_keyed_request(context, entry, request_caps())
  let outcome = match result {
    Ok(_) => "accepted"
    Err(e) =>
      match e.kind {
        MissingCorrelation => "MissingCorrelation"
        CorrelationField(_) => "CorrelationField"
        UnknownField(_) => "UnknownField"
        MissingField(_) => "MissingField"
        Literal(_) => "Literal"
        IncompatibleParameter(_) => "IncompatibleParameter"
        IncompatibleBinding(_) => "IncompatibleBinding"
        _ => "unexpected"
      }
  }
  assert_eq(outcome, expected)
  assert_true(
    check_keyed_request(context, entry, { ..request_caps(), max_work: -1, })
    is Err(e) &&
    e.kind == InvalidLimits,
  )
  let foreign = at(resolve(source_inputs, catalog, caps()).unwrap(), 0).unwrap()
  assert_true(
    check_keyed_request(context, foreign, request_caps()) is Err(e) &&
    e.kind == ForeignInput,
  )
  if result is Err(e) {
    assert_true(e.source is Some(_))
    if e.kind is CorrelationField(name) {
      let path = @decode.cursor_path(e.source.unwrap())
      assert_eq(path[path.length() - 1], @source.Key(name))
      assert_true(@decode.cursor_key_span(e.source.unwrap()) is Some(_))
    }
    return
  }
  let v = result.unwrap()
  let supplied = if @parameters.declaration_count(
      @stages.declarations(@inputs.source(source_inputs)),
    ) ==
    0 {
    "{}"
  } else {
    "{\"tenant\":null}"
  }
  let values = supplied_values(source_inputs, supplied)
  let parameters = prepare_request_parameters(context, values, 1000000).unwrap()
  let bound = bind_keyed_request_parameters(parameters, v, 1000000).unwrap()
  assert_true(physical_equal(parameterized_keyed_request(bound), v))
  assert_true(
    physical_equal(parameterized_keyed_request_parameters(bound), parameters),
  )
  assert_eq(
    parameterized_keyed_request_field_count(bound),
    keyed_request_field_count(v),
  )
  let mut host_bindings = 0
  for i in 0..<keyed_request_field_count(v) {
    let original = keyed_request_field_at(v, i).unwrap()
    let field = parameterized_keyed_request_field_at(bound, i).unwrap()
    assert_true(physical_equal(field.field, original))
    match (original.value, field.value) {
      (LiteralValue(a), CheckedLiteral(b)) => assert_true(physical_equal(a, b))
      (ParameterValue(a), BoundParameter(b)) =>
        assert_true(
          physical_equal(a.parameter_type, @parameters.bound_parameter_type(b)),
        )
      (BindingValue(a), UnboundHostBinding(b)) => {
        assert_true(physical_equal(a, b))
        host_bindings += 1
      }
      _ => fail("keyed binding changed the value role")
    }
  }
  assert_eq(
    parameterized_keyed_request_host_binding_count(bound),
    host_bindings,
  )
  let binding_work = parameterized_keyed_request_work(bound)
  assert_true(
    bind_keyed_request_parameters(parameters, v, binding_work) is Ok(_),
  )
  if binding_work > 0 {
    assert_true(
      bind_keyed_request_parameters(parameters, v, binding_work - 1)
      is Err(WorkLimit),
    )
  }
  assert_true(
    bind_keyed_request_parameters(parameters, v, -1) is Err(InvalidLimits),
  )
  let other_context = prepare_requests(
    resolved,
    request_slots(source_inputs),
    1000000,
  ).unwrap()
  let other_parameters = prepare_request_parameters(
    other_context, values, 1000000,
  ).unwrap()
  assert_true(
    bind_keyed_request_parameters(other_parameters, v, 1000000)
    is Err(ForeignRequest),
  )
  assert_true(
    parameterized_keyed_request_field_at(bound, keyed_request_field_count(v))
    is None,
  )
  assert_true(physical_equal(keyed_request_context(v), context))
  assert_true(physical_equal(keyed_request_input(v), entry))
  assert_true(
    physical_equal(
      keyed_request_correlation(v),
      @environment.source_request_correlation(selected_contract(entry)).unwrap(),
    ),
  )
  let (work, pairs, nodes, text) = keyed_request_usage(v)
  let exact : RequestLimits = {
    max_work: work,
    max_pairs: pairs,
    values: { ..request_caps().values, max_nodes: nodes, max_text_bytes: text, },
  }
  assert_true(check_keyed_request(context, entry, exact) is Ok(_))
  assert_true(
    check_keyed_request(context, entry, { ..exact, max_work: work - 1, })
    is Err(e) &&
    e.kind == WorkLimit,
  )
  if pairs > 0 {
    assert_true(
      check_keyed_request(context, entry, { ..exact, max_pairs: pairs - 1, })
      is Err(e) &&
      e.kind == PairLimit,
    )
  }
  if nodes > 0 {
    assert_true(
      check_keyed_request(context, entry, {
        ..exact,
        values: { ..exact.values, max_nodes: nodes - 1, },
      })
      is Err(_),
    )
  }
  if text > 0 {
    assert_true(
      check_keyed_request(context, entry, {
        ..exact,
        values: { ..exact.values, max_text_bytes: text - 1, },
      })
      is Err(_),
    )
  }
  for i in 0..<keyed_request_field_count(v) {
    let field = keyed_request_field_at(v, i).unwrap()
    assert_true(field.slot.field_name != "id")
  }
  assert_true(keyed_request_field_at(v, -1) is None)
  assert_true(keyed_request_field_at(v, keyed_request_field_count(v)) is None)
  assert_true(
    check_direct_request(context, entry, request_caps()) is Err(e) &&
    e.kind == MissingField("id"),
  )
}
