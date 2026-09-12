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
}
