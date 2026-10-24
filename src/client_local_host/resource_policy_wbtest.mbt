///|
test "Local materialized row default is a necessary bound from the original byte policy" {
  let policy=client_local_resource_policy()
  assert_true(physical_equal(policy,client_local_resource_policy()))
  let rows=client_local_materialized_row_ceiling(policy).unwrap()
  let unit=@execution.execution_capacity_node_bytes()
  assert_true(rows.to_int64()*unit<=policy.retained_bytes)
  assert_true((rows.to_int64()+1L)*unit>policy.retained_bytes)
  assert_eq(rows,2097152)
  assert_eq(client_local_joint_byte_ceiling(),536870912L)
  let foreign : ClientLocalResourcePolicy={retained_bytes:policy.retained_bytes,execution_bytes:policy.execution_bytes}
  assert_true(client_local_materialized_row_ceiling(foreign) is None)
}
