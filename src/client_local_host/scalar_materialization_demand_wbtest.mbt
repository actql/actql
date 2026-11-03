///|
fn materialization_test_inventory() -> ClientLocalSchemaProofInventory {
  {
    original_count: 1,
    _observed_owner_count: 1,
    _observed_work_used: 2,
    max_node_width: 2L,
    closed_value_nodes: None,
    max_name_width: 2L,
    fields: 1,
    names: 2,
    ports: 0,
    bindings: 0,
    closed_rows: Some(100000),
  }
}

///|
test "scalar materialization demand separates original inventory from numeric projections" {
  let original = materialization_test_inventory()
  let demand = client_local_scalar_demand(original, 100000).unwrap()
  assert_true(physical_equal(demand.original, original))
  assert_false(
    physical_equal(demand.original, materialization_test_inventory()),
  )
  assert_eq(demand.value_nodes, 200000)
  assert_eq(demand.name_bytes, 200000)
  assert_eq(demand.wire_bytes, 4400030)
  let (values, execution, measurement) = client_local_execution_limits(
    max_rows=100000,
    scalar_inventory=Some(original),
    scalar_demand=Some(demand),
  )
  assert_eq(values.max_nodes, 200000)
  assert_eq(execution.rows.max_rows, 100000)
  assert_eq(measurement.max_nodes, 200000)
  assert_eq(measurement.max_bytes, 4400030)
  // The demand is not a Ledger grant. Its values are inputs to the unchanged
  // complete provider/Run capacity calculator and original resource policy.
}

///|
test "scalar materialization demand rejects representation overflow not arbitrary row ceilings" {
  assert_eq(client_local_scalar_node_limit(2, 100000), Some(200000))
  assert_eq(client_local_scalar_node_limit(100, 201), Some(20100))
  assert_eq(client_local_scalar_node_limit(1, 20001), Some(20001))
  assert_eq(client_local_scalar_node_limit(1, 2147483644), Some(2147483644))
  assert_eq(client_local_scalar_node_limit(1, 2147483645), None)
  assert_eq(
    client_local_scalar_wire_byte_bound(2147483647, 2147483647, 2147483647),
    None,
  )
  assert_eq(client_local_scalar_product(2147483647L, 2147483647, 0), None)
  assert_true(
    client_local_scalar_demand(materialization_test_inventory(), 0) is None,
  )
  assert_true(
    client_local_scalar_demand(materialization_test_inventory(), 2147483647)
    is None,
  )
}
