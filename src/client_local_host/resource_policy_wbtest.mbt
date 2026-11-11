///|
test "Local materialized row default is a necessary bound from the original byte policy" {
  let policy = client_local_resource_policy()
  assert_true(physical_equal(policy, client_local_resource_policy()))
  let rows = client_local_materialized_row_ceiling(policy).unwrap()
  let unit = @execution.execution_capacity_node_bytes()
  assert_true(rows.to_int64() * unit <= policy.retained_bytes)
  assert_true((rows.to_int64() + 1L) * unit > policy.retained_bytes)
  assert_eq(rows, 2097152)
  assert_eq(client_local_joint_byte_ceiling(), 536870912L)
  // Equal current policy fields are still a foreign allocation, not authority.
  let foreign : ClientLocalResourcePolicy = {
    retained_bytes: policy.retained_bytes,
    execution_bytes: policy.execution_bytes,
    dispatch_planning_work: policy.dispatch_planning_work,
    graph_work: policy.graph_work,
    relation_wire_bytes: policy.relation_wire_bytes,
  }
  assert_false(physical_equal(policy, foreign))
  assert_true(client_local_materialized_row_ceiling(foreign) is None)
}

///|
test "source-free work selection preserves the default and finite typed bounds" {
  assert_eq(client_local_source_free_max_work(None), Some(20000000))
  assert_eq(client_local_source_free_max_work(Some(30000000)), Some(30000000))
  assert_eq(
    client_local_source_free_max_work(Some(2147483647)),
    Some(2147483647),
  )
  assert_true(client_local_source_free_max_work(Some(0)) is None)
  assert_true(client_local_source_free_max_work(Some(-1)) is None)
}
