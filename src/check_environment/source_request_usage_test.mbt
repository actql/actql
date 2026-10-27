///|
test "original Source request observer retains first-role prefix and same successful usage" {
  let correlation = correlation_fixture()
  guard correlation is Object(fields) else { abort("correlation fixture") }
  fields["request_fields"] = @json.parse("[\"missing\",\"id\"]")
  let carriers = request_carriers(
    record_body(),
    record_body(),
    Some(correlation),
  )
  let modes = carrier_schema_modes(carriers)
  let refs = data_policy_references(
    value_contract_policies(source_view_shape_values(read_mode_shapes(modes))),
  )
  let root = member_body(read_mode_member(read_mode_view_at(modes, 0).unwrap()))
  let acquisition = @decode.required(
    @decode.open_object(root).unwrap(),
    "acquisition",
  ).unwrap()
  let correlation_source = @decode.required(
    @decode.open_object(acquisition).unwrap(),
    "correlation",
  ).unwrap()
  let expected = reference_usage(refs).1 +
    @decode.object_length(root).unwrap() +
    1 +
    @decode.object_length(acquisition).unwrap() +
    1 +
    @decode.object_length(correlation_source).unwrap() +
    1 +
    "missing".length() +
    1
  let (result, work, roles) = observe_source_request_contracts(
    carriers,
    request_limits(),
  )
  assert_true(
    result is Err(issue) && issue.kind == UnknownRequestField("missing"),
  )
  assert_eq(work, expected)
  assert_eq(roles, 6)
  let valid = request_carriers(
    record_body(),
    record_body(),
    Some(correlation_fixture()),
  )
  let (result, work, roles) = observe_source_request_contracts(
    valid,
    request_limits(),
  )
  let original = result.unwrap()
  assert_eq(source_request_usage(original), (work, roles, 1))
  assert_eq(roles, 6)
  let (result, work, roles) = observe_source_request_contracts(valid, {
    max_work: -1,
    max_roles: 1,
  })
  assert_true(result is Err(issue) && issue.kind == InvalidLimits)
  assert_eq((work, roles), (0, 0))
}

///|
test "original Content request refusal retains its nested lookup work" {
  let valid = content_fixture_carriers()
  let (accepted, original_work, original_roles) = observe_source_request_contracts(
    valid,
    request_limits(),
  )
  assert_true(accepted is Ok(_))
  // Canonical fixture emission places version last. All other fields and the
  // Source request prefix have identical lengths and typed meaning.
  let capacity = content_fixture_capacity()
  mutate_reference_fixture(capacity, ["version"], 0, Some(Json::string("bad")))
  let invalid = content_fixture_carriers(capacity=Some(capacity))
  let modes = carrier_schema_modes(invalid)
  let refs = data_policy_references(
    value_contract_policies(source_view_shape_values(read_mode_shapes(modes))),
  )
  let root = member_body(read_mode_member(read_mode_view_at(modes, 0).unwrap()))
  let output = @decode.required(@decode.open_object(root).unwrap(), "output").unwrap()
  let slot = @decode.required(@decode.open_object(output).unwrap(), "facts").unwrap()
  let facts = reference_contract(
    catalog_reference_for_cursor(refs, slot).unwrap(),
  )
  let source = @decode.required(
    @decode.open_object(contract_body(facts)).unwrap(),
    "lookup_capacity",
  ).unwrap()
  assert_eq(@decode.field_at(source, 4).unwrap().0, "version")
  let (refused, failed_work, failed_roles) = observe_source_request_contracts(
    invalid,
    request_limits(),
  )
  assert_true(refused is Err(issue) && issue.kind == InvalidFileContentProfile)
  assert_eq(failed_roles, original_roles)
  assert_eq(
    failed_work,
    original_work - "actql-lookup-capacity/0.1".length() + "bad".length(),
  )
}
