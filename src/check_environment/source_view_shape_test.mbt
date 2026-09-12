///|
test "SourceView schema admission is distinct from already admitted references" {
  let values = check_protocol_value_contracts(
    value_policies(value_bodies("{\"type\":\"number\",\"nullable\":false}")),
    protocol_value_limits(),
  ).unwrap()
  // The existing role-reference fixture deliberately omits SourceView members
  // unrelated to reference traversal. It cannot become complete shape evidence.
  assert_true(
    check_source_view_shapes(values, { max_work: 100000, max_views: 10, })
    is Err(e) &&
    e.kind is MissingField(_),
  )
  assert_true(
    check_source_view_shapes(values, { max_work: 100000, max_views: 0, })
    is Err(e) &&
    e.kind == ViewLimit,
  )
  assert_true(
    check_source_view_shapes(values, { max_work: -1, max_views: 10, }) is Err(e) &&
    e.kind == InvalidLimits,
  )
  let refs = check_catalog_references(
    check_catalog_contents(catalog_environment([], []), caps()).unwrap(),
    reference_caps(),
  ).unwrap()
  let empty = check_protocol_value_contracts(
    check_source_data_policies(refs, policy_limits()).unwrap(),
    protocol_value_limits(),
  ).unwrap()
  let shapes = check_source_view_shapes(empty, { max_work: 0, max_views: 0, }).unwrap()
  assert_true(physical_equal(source_view_shape_values(shapes), empty))
  assert_eq(source_view_shape_usage(shapes), (0, 0))
  assert_true(source_view_shape_at(shapes, 0) is None)
  let modes = check_source_read_modes(shapes, 0).unwrap()
  assert_true(physical_equal(read_mode_shapes(modes), shapes))
  assert_eq(read_mode_usage(modes), (0, 0))
  assert_true(read_mode_view_at(modes, 0) is None)
  assert_true(
    check_source_read_modes(shapes, -1) is Err(e) && e.kind == InvalidLimits,
  )
  let carrier_limits : CarrierSchemaLimits = {
    max_work: 0,
    max_schemas: 0,
    bodies: { max_bytes: 0, max_nodes: 0, max_depth: 0, },
  }
  let carriers = check_carrier_schemas(modes, carrier_limits).unwrap()
  assert_eq(carrier_schema_usage(carriers), (0, 0, 0, 0))
  assert_true(physical_equal(carrier_schema_modes(carriers), modes))
  assert_true(carrier_schema_at(carriers, 0) is None)
  let requests = check_source_request_contracts(carriers, {
    max_work: 0,
    max_roles: 0,
  }).unwrap()
  assert_eq(source_request_usage(requests), (0, 0, 0))
  assert_true(physical_equal(source_request_carriers(requests), carriers))
  assert_true(
    check_carrier_schemas(modes, { ..carrier_limits, max_work: -1, }) is Err(e) &&
    e.kind == InvalidLimits,
  )
}
