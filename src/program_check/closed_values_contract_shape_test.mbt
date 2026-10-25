///|
test "closed Values contract shape validates actual checked one-stage original" {
  let (_, _, environment, _, limits) = public_input_fixture()
  let catalog = @program_check.prepare_source_catalog(environment, {
    max_work: 10000000, max_bytes: 1000000, max_nodes: 100000, max_depth: 100,
  }).unwrap()
  let dependencies = @program_check.source_catalog_closed_values_dependencies(catalog, 1000000).unwrap()
  assert_eq(@program_check.source_catalog_closed_values_dependencies(catalog, dependencies.scanned_work), Some(dependencies))
  if dependencies.scanned_work > 0 {
    assert_true(@program_check.source_catalog_closed_values_dependencies(catalog, dependencies.scanned_work - 1) is None)
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"closed\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"v\"}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[\"id\"]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let checked = public_checked(
    @program_check.check_document(
      document,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  let requirements = @program_check.requirements(checked)
  let operations = @context.stage_requirement_operations(requirements)
  assert_eq(@context.operation_closure_count(operations), 1)
  let inventory = @program_check.contract_inventory(checked)
  let shape = @context.closed_values_contract_shape()
  assert_eq(@context.core_contract_root_count(inventory), shape.roots)
  assert_eq(@context.core_contract_body_count(inventory), shape.bodies)
  assert_eq(@context.core_contract_usage(inventory).1, shape.visited_edges)
  assert_eq(@program_check.unit_contract_count(checked, 0), Some(shape.bodies))
}

///|
test "closed Values public policy owner dependency quote keeps all dimensions" {
  assert_eq(@environment.closed_values_policy_owner_layout(-1), None)
  let a = @environment.closed_values_policy_owner_layout(2).unwrap()
  let b = @environment.closed_values_policy_owner_layout(3).unwrap()
  assert_true(b.record_headers > a.record_headers)
  assert_true(b.reference_slots > a.reference_slots)
  assert_true(b.scalar_words > a.scalar_words)
  assert_eq(a.owned_wire_bytes, 1715L)
  assert_eq(a.owned_utf16_units, 2340L)
  let largest = @environment.closed_values_policy_owner_layout(2147483647).unwrap()
  assert_true(largest.scalar_words > b.scalar_words)
}
