///|
fn supplied_values(
  inputs : @inputs.Inputs,
  supplied : String,
) -> @parameters.BoundValues {
  let node = @source.parse_json(supplied, {
    max_input_bytes: 1000000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 10000,
    max_depth: 100,
    max_string_bytes: 1000000,
    max_total_string_bytes: 1000000,
  }).unwrap()
  let ready = @parameters.bind(
    @stages.declarations(@inputs.source(inputs)),
    Some(cursor),
    request_caps().values,
  ).unwrap()
  guard ready is @parameters.Ready(values) else {
    abort("incomplete fixture bindings")
  }
  values
}

///|
fn check_request_parameters_fixture(
  wire : String,
  cid : String,
  input : String,
  declarations : String,
  supplied : String,
) -> Unit raise {
  let inputs = fixture_inputs(input, declarations~)
  let resolved = resolve(inputs, fixture_catalog(wire, cid), caps()).unwrap()
  let context = prepare_requests(resolved, request_slots(inputs), 1000000).unwrap()
  let request = check_direct_request(
    context,
    at(resolved, 0).unwrap(),
    request_caps(),
  ).unwrap()
  let values = supplied_values(inputs, supplied)
  let prepared = prepare_request_parameters(context, values, 1000000).unwrap()
  assert_true(physical_equal(request_parameter_context(prepared), context))
  assert_true(physical_equal(request_parameter_values(prepared), values))
  assert_true(
    prepare_request_parameters(
      context,
      values,
      request_parameter_work(prepared),
    )
    is Ok(_),
  )
  assert_true(
    prepare_request_parameters(
      context,
      values,
      request_parameter_work(prepared) - 1,
    )
    is Err(WorkLimit),
  )
  assert_true(
    prepare_request_parameters(context, values, -1) is Err(InvalidLimits),
  )
  let bound = bind_request_parameters(prepared, request, 1000000).unwrap()
  assert_true(physical_equal(parameterized_request(bound), request))
  assert_true(physical_equal(parameterized_request_parameters(bound), prepared))
  assert_eq(
    parameterized_request_field_count(bound),
    request_field_count(request),
  )
  let mut pending = 0
  for i in 0..<parameterized_request_field_count(bound) {
    let field = parameterized_request_field_at(bound, i).unwrap()
    assert_true(
      physical_equal(field.field, request_field_at(request, i).unwrap()),
    )
    match (field.value, field.field.value) {
      (CheckedLiteral(v), LiteralValue(original)) =>
        assert_true(physical_equal(v, original))
      (BoundParameter(v), ParameterValue(d)) => {
        assert_eq(v.name, d.name)
        assert_true(
          physical_equal(@parameters.bound_parameter_type(v), d.parameter_type),
        )
        let mut found = false
        for j in 0..<@parameters.bound_value_count(values) {
          if physical_equal(v, @parameters.bound_value_at(values, j).unwrap()) {
            found = true
          }
        }
        assert_true(found)
      }
      (UnboundHostBinding(v), BindingValue(d)) => {
        assert_true(physical_equal(v, d))
        pending += 1
      }
      _ => fail("request binding changed value role")
    }
  }
  assert_eq(parameterized_request_host_binding_count(bound), pending)
  if pending > 0 {
    assert_true(
      parameterized_request_wire(bound, 1000000, 10000, 100)
      is Err(UnboundHostBinding),
    )
    assert_true(
      parameterized_request_canonical_geometry(bound, 1000000, 10000, 100)
      is Err(UnboundHostBinding),
    )
  } else {
    let json_fields = []
    guard @json.parse(wire) is Object(catalog) &&
      catalog.get("contract_registry") is Some(Array(envelopes)) else {
      abort("invalid authored Catalog fixture")
    }
    for envelope in envelopes {
      if envelope is Object(fields) &&
        fields.get("kind") == Some(Json::string("request_schema")) &&
        fields.get("body") is Some(Object(body)) &&
        body.get("fields") is Some(Object(schema)) {
        for name, contract in schema {
          if contract is Object(type_fields) &&
            type_fields.get("type") == Some(Json::string("json")) {
            json_fields.push(name)
          }
        }
      }
    }
    let wire = parameterized_request_wire(bound, 1000000, 10000, 100).unwrap()
    let geometry = parameterized_request_canonical_geometry(
      bound, 1000000, 10000, 100,
    ).unwrap()
    let canonical = parameterized_request_canonical_document(
      bound, 1000000, 10000, 100,
    ).unwrap()
    assert_eq(
      @encode.construction_geometry_usage(geometry),
      @encode.document_usage(canonical),
    )
    assert_true(geometry.objects >= 1)
    assert_true(geometry.fields >= parameterized_request_field_count(bound))
    assert_true(
      parameterized_request_canonical_geometry(bound, 1, 10000, 100) is Err(_),
    )
    // Resolve expectations from authored input and supplied/default values,
    // not from the checked fields or the product encoder's output.
    let expected : Map[String, Json] = Map([])
    let authored = match @json.parse(input) {
      Object(fields) =>
        match fields.get("request") {
          Some(Object(request)) => request
          None => Map([])
          _ => abort("invalid authored Request fixture")
        }
      _ => abort("invalid authored input fixture")
    }
    let supplied = match @json.parse(supplied) {
      Object(values) => values
      _ => abort("invalid authored Parameter fixture")
    }
    let defaults = match @json.parse("{" + declarations + "\"fixture\":0}") {
      Object(root) =>
        match root.get("params") {
          Some(Object(values)) => values
          None => Map([])
          _ => abort("invalid authored declarations fixture")
        }
      _ => abort("invalid authored declarations fixture")
    }
    for name, value in authored {
      let value = match value {
        Object(fields) if fields.length() == 1 =>
          match fields.get("$param") {
            Some(String(parameter)) =>
              match supplied.get(parameter) {
                Some(value) => value
                None =>
                  match defaults.get(parameter) {
                    Some(Object(declaration)) =>
                      declaration.get("default").unwrap()
                    _ => abort("missing authored Parameter expectation")
                  }
              }
            _ => value
          }
        _ => value
      }
      // Json scalars keep the existing typed-wire marker. Nested business
      // $param/$binding keys remain data, never additional Request slots.
      expected[name] = if json_fields.contains(name) && value != Json::null() {
        Json::object(Map([("$json", value)]))
      } else {
        value
      }
    }
    assert_eq(@json.parse(wire), Json::object(expected))
    let bytes = @utf8.encode(wire).length()
    assert_eq(
      parameterized_request_wire(bound, bytes, 10000, 100).unwrap(),
      wire,
    )
    assert_true(
      parameterized_request_wire(bound, bytes - 1, 10000, 100)
      is Err(Encoding(_)),
    )
    assert_true(
      parameterized_request_wire(bound, bytes, 0, 100) is Err(Encoding(_)),
    )
  }
  let requirements = direct_request_bindings(bound, 1000000, pending).unwrap()
  assert_true(
    request_bindings_request(requirements) is DirectBindingRequest(owner) &&
    physical_equal(owner, bound),
  )
  check_binding_requirements(
    requirements,
    parameterized_request_field_count(bound),
    pending,
    i => parameterized_request_field_at(bound, i),
  )
  let work = request_bindings_work(requirements)
  assert_true(direct_request_bindings(bound, work, pending) is Ok(_))
  assert_true(
    direct_request_bindings(bound, work - 1, pending) is Err(WorkLimit),
  )
  assert_true(direct_request_bindings(bound, -1, pending) is Err(InvalidLimits))
  assert_true(direct_request_bindings(bound, work, -1) is Err(InvalidLimits))
  if pending > 0 {
    assert_true(
      direct_request_bindings(bound, work, pending - 1) is Err(BindingLimit),
    )
  }
  assert_true(parameterized_request_field_at(bound, -1) is None)
  assert_true(
    parameterized_request_field_at(
      bound,
      parameterized_request_field_count(bound),
    )
    is None,
  )
  let work = parameterized_request_work(bound)
  assert_true(bind_request_parameters(prepared, request, work) is Ok(_))
  if work > 0 {
    assert_true(
      bind_request_parameters(prepared, request, work - 1) is Err(WorkLimit),
    )
  }
  assert_true(
    bind_request_parameters(prepared, request, -1) is Err(InvalidLimits),
  )
  let other_inputs = fixture_inputs(input, declarations~)
  assert_true(
    prepare_request_parameters(
      context,
      supplied_values(other_inputs, supplied),
      1000000,
    )
    is Err(ForeignDeclarations),
  )
  let other_context = prepare_requests(resolved, request_slots(inputs), 1000000).unwrap()
  let other_request = check_direct_request(
    other_context,
    at(resolved, 0).unwrap(),
    request_caps(),
  ).unwrap()
  assert_true(
    bind_request_parameters(prepared, other_request, 1000000)
    is Err(ForeignRequest),
  )
  let index = @references.prepare_values(values, max_work=1000).unwrap()
  assert_true(physical_equal(@references.prepared_values(index), values))
  assert_true(
    @references.prepared_value_for(
      index,
      @stages.declarations(@inputs.source(inputs)),
      "absent",
    )
    is None,
  )
  for j in 0..<@parameters.bound_value_count(values) {
    let v = @parameters.bound_value_at(values, j).unwrap()
    assert_true(
      @references.prepared_value_for(
        index,
        @stages.declarations(@inputs.source(other_inputs)),
        v.name,
      )
      is None,
    )
  }
}
