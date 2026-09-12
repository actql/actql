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
