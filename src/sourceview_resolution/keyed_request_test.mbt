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
  check_keyed_row_request_instance(bound, input, supplied)
  let requirements = keyed_request_bindings(bound, 1000000, host_bindings).unwrap()
  assert_true(
    request_bindings_request(requirements) is KeyedBindingRequest(owner) &&
    physical_equal(owner, bound),
  )
  check_binding_requirements(
    requirements,
    parameterized_keyed_request_field_count(bound),
    host_bindings,
    i => parameterized_keyed_request_field_at(bound, i),
  )
  let requirement_work = request_bindings_work(requirements)
  assert_true(
    keyed_request_bindings(bound, requirement_work, host_bindings) is Ok(_),
  )
  assert_true(
    keyed_request_bindings(bound, requirement_work - 1, host_bindings)
    is Err(WorkLimit),
  )
  assert_true(
    keyed_request_bindings(bound, -1, host_bindings) is Err(InvalidLimits),
  )
  if host_bindings > 0 {
    assert_true(
      keyed_request_bindings(bound, requirement_work, host_bindings - 1)
      is Err(BindingLimit),
    )
  }
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

///|
/// Exercise concrete requests under the real corpus Catalog/parameter owners.
/// The numeric correlation role in these independent fixtures is `id`.
fn check_keyed_row_request_instance(
  bound : ParameterizedKeyedRequest,
  input : String,
  supplied : String,
) -> Unit raise {
  let numeric_key = @value.number_value(7.0).unwrap()
  if parameterized_keyed_request_host_binding_count(bound) != 0 {
    assert_true(
      start_keyed_row_request(bound, [numeric_key], request_caps())
      is Err(UnboundHostBinding),
    )
    return
  }
  // Copy admission (2), start/name (3), scalar node (1), shared completion
  // (1), request completion (1). Authored fields add name + retention visit.
  let mut expected_work = 8
  for i in 0..<parameterized_keyed_request_field_count(bound) {
    expected_work += parameterized_keyed_request_field_at(bound, i).unwrap().field.slot.field_name.length() +
      1
  }
  let exact : RequestLimits = {
    max_work: expected_work,
    max_pairs: parameterized_keyed_request_field_count(bound) + 1,
    values: { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  }
  let cursor = start_keyed_row_request(bound, [numeric_key], exact).unwrap()
  assert_true(advance_keyed_row_request(cursor) is KeyedRowRequestContinue)
  assert_true(advance_keyed_row_request(cursor) is KeyedRowRequestContinue)
  assert_true(advance_keyed_row_request(cursor) is KeyedRowRequestContinue)
  guard advance_keyed_row_request(cursor) is KeyedRowRequestComplete(row) else {
    fail("typed keyed request did not finish within the independent work bound")
  }
  assert_true(physical_equal(keyed_row_request_owner(row), bound))
  assert_eq(keyed_row_request_usage(row), (expected_work, 1, 0))
  let expected = Map([])
  expected["id"] = @json.parse("7")
  guard @json.parse(input) is Object(authored) &&
    @json.parse(supplied) is Object(parameters) else {
    fail("invalid independent request fixture")
  }
  if authored.get("request") is Some(Object(fields)) {
    for name, value in fields {
      expected[name] = match value {
        Object(marker) if marker.length() == 1 =>
          match marker.get("$param") {
            Some(String(name)) => parameters.get(name).unwrap()
            _ => value
          }
        _ => value
      }
    }
  }
  for i in 0..<parameterized_keyed_request_field_count(bound) {
    let field = parameterized_keyed_request_field_at(bound, i).unwrap().field
    if field.contract.shape is @contract.Json {
      expected[field.slot.field_name] = Json::object({
        "$json": expected.get(field.slot.field_name).unwrap(),
      })
    }
  }
  let wire = keyed_row_request_wire(row, 10000, 1000, 30).unwrap()
  assert_eq(@json.parse(wire), Json::object(expected))
  check_keyed_request_wire_cursor(row, wire)
  check_keyed_row_response_instance(row, numeric_key)
  // A completed cursor has transferred its fields. A later cancel/advance must
  // neither mutate the handed-off request nor create another completion.
  cancel_keyed_row_request(cursor)
  assert_true(
    advance_keyed_row_request(cursor) is KeyedRowRequestFailed(Closed),
  )
  assert_eq(keyed_row_request_wire(row, 10000, 1000, 30).unwrap(), wire)
  assert_true(keyed_row_request_wire(row, 0, 1000, 30) is Err(_))
  assert_true(keyed_row_request_wire(row, 10000, 0, 30) is Err(_))
  assert_true(
    start_keyed_row_request(bound, [], exact) is Err(CorrelationArity),
  )
  assert_true(
    start_keyed_row_request(bound, [numeric_key], {
      ..exact,
      max_pairs: exact.max_pairs - 1,
    })
    is Err(PairLimit),
  )
  for invalid in [@value.null_value(), @value.text_value("7", 1).unwrap()] {
    let invalid_cursor = start_keyed_row_request(bound, [invalid], exact).unwrap()
    assert_true(
      advance_keyed_row_request(invalid_cursor) is KeyedRowRequestContinue,
    )
    assert_true(
      advance_keyed_row_request(invalid_cursor)
      is KeyedRowRequestFailed(InvalidCorrelation(0)),
    )
    assert_true(
      advance_keyed_row_request(invalid_cursor) is KeyedRowRequestFailed(Closed),
    )
  }
  let short = start_keyed_row_request(bound, [numeric_key], {
    ..exact,
    max_work: expected_work - 1,
  }).unwrap()
  assert_true(advance_keyed_row_request(short) is KeyedRowRequestContinue)
  assert_true(advance_keyed_row_request(short) is KeyedRowRequestContinue)
  assert_true(advance_keyed_row_request(short) is KeyedRowRequestContinue)
  assert_true(
    advance_keyed_row_request(short) is KeyedRowRequestFailed(WorkLimit),
  )
  assert_eq(keyed_row_request_work(short), expected_work - 1)
  cancel_keyed_row_request(short)
  assert_eq(keyed_row_request_work(short), expected_work - 1)
  let cancelled = start_keyed_row_request(bound, [numeric_key], exact).unwrap()
  assert_true(advance_keyed_row_request(cancelled) is KeyedRowRequestContinue)
  let cancelled_work = keyed_row_request_work(cancelled)
  cancel_keyed_row_request(cancelled)
  cancel_keyed_row_request(cancelled)
  assert_true(
    advance_keyed_row_request(cancelled) is KeyedRowRequestFailed(Closed),
  )
  assert_eq(keyed_row_request_work(cancelled), cancelled_work)
  let no_nodes = start_keyed_row_request(bound, [numeric_key], {
    ..exact,
    values: { ..exact.values, max_nodes: 0, },
  }).unwrap()
  assert_true(advance_keyed_row_request(no_nodes) is KeyedRowRequestContinue)
  assert_true(
    advance_keyed_row_request(no_nodes)
    is KeyedRowRequestFailed(InvalidCorrelation(0)),
  )
}

///|
fn check_keyed_row_response_instance(
  request : KeyedRowRequest,
  key : @value.Value,
) -> Unit raise {
  // Copy/start 2, role start 1, shared numeric recheck 2, equality poll/node
  // 2, equality completion poll 1, response completion poll 1 = 9.
  let limits : RequestLimits = {
    max_work: 9,
    max_pairs: 1,
    values: { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  }
  let cursor = start_keyed_row_response(request, [key], limits).unwrap()
  for _ in 0..<5 {
    assert_true(advance_keyed_row_response(cursor) is KeyedRowResponseContinue)
  }
  assert_true(advance_keyed_row_response(cursor) is KeyedRowResponseComplete)
  assert_eq(keyed_row_response_work(cursor), 9)
  assert_true(
    advance_keyed_row_response(cursor) is KeyedRowResponseFailed(Closed),
  )
  cancel_keyed_row_response(cursor)
  assert_eq(keyed_row_response_work(cursor), 9)
  for
    (value, mismatch) in [
      (@value.number_value(8.0).unwrap(), true),
      (@value.null_value(), false),
      (@value.text_value("7", 1).unwrap(), false),
    ] {
    let cursor = start_keyed_row_response(request, [value], limits).unwrap()
    let mut failure = None
    for _ in 0..<6 {
      match advance_keyed_row_response(cursor) {
        KeyedRowResponseContinue => ()
        KeyedRowResponseFailed(issue) => {
          failure = Some(issue)
          break
        }
        KeyedRowResponseComplete => fail("invalid response key completed")
      }
    }
    assert_eq(
      failure,
      Some(
        if mismatch {
          CorrelationMismatch(0)
        } else {
          InvalidCorrelation(0)
        },
      ),
    )
    let work = keyed_row_response_work(cursor)
    cancel_keyed_row_response(cursor)
    assert_eq(keyed_row_response_work(cursor), work)
  }
  let short = start_keyed_row_response(request, [key], {
    ..limits,
    max_work: 8,
  }).unwrap()
  for _ in 0..<4 {
    assert_true(advance_keyed_row_response(short) is KeyedRowResponseContinue)
  }
  assert_true(
    advance_keyed_row_response(short) is KeyedRowResponseFailed(WorkLimit),
  )
  assert_eq(keyed_row_response_work(short), 8)
  let cancelled = start_keyed_row_response(request, [key], limits).unwrap()
  for _ in 0..<3 {
    assert_true(
      advance_keyed_row_response(cancelled) is KeyedRowResponseContinue,
    )
  }
  let work = keyed_row_response_work(cancelled)
  cancel_keyed_row_response(cancelled)
  cancel_keyed_row_response(cancelled)
  assert_true(
    advance_keyed_row_response(cancelled) is KeyedRowResponseFailed(Closed),
  )
  assert_eq(keyed_row_response_work(cancelled), work)
  assert_true(
    start_keyed_row_response(request, [], limits) is Err(CorrelationArity),
  )
  assert_true(
    start_keyed_row_response(request, [key, key], limits)
    is Err(CorrelationArity),
  )
}
