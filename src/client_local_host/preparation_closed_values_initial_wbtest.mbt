///|
test "closed Values initial recipe has one owned control tariff and combined exact scanner boundary" {
  let policy = client_local_resource_policy()
  let (retained, execution) = client_closed_values_initial_control_capacity(
    policy,
  ).unwrap()
  assert_eq(
    preparation_node_own_data_scan_cost().unwrap() +
    preparation_node_own_data_header_cost().unwrap(),
    416L,
  )
  assert_eq(
    execution,
    416L +
    preparation_representation_cost(closed_values_projection_scratch_units()).unwrap(),
  )
  assert_eq(
    retained,
    preparation_representation_cost(closed_values_initial_control_units()).unwrap(),
  )
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  for allowance in [execution - 1L, execution] {
    let ledger = @resources.create_ledger({
      ..limits,
      retained_bytes: retained,
      execution_bytes: allowance,
    }).unwrap()
    let input = [1]
    let result : Result[
      @resources.PreparationCapacity[Array[Int], Array[Int]],
      @resources.PreparationCapacityIssue,
    ] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      retained,
      execution,
      max_borrowers=1,
    )
    if allowance == execution - 1L {
      assert_true(
        result
        is Err(
          @resources.PreparationCapacityIssue::Resource(
            @resources.LedgerIssue::ExecutionLimit
          )
        ),
      )
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    } else {
      assert_true(result is Ok(_))
      let usage = @resources.ledger_usage(ledger)
      assert_eq(usage.reserved_retention_bytes, retained)
      assert_eq(usage.reserved_execution_bytes, execution)
      assert_eq(usage.peak_retention_bytes, retained)
      let owner = result.unwrap()
      let actual = @resources.preparation_capacity_accounting(owner)
      assert_eq(
        actual,
        (retained, execution, 0L, retained, retained, execution),
      )
      assert_eq(
        @resources.abort_preparation_capacity_after_cleanup(owner, input),
        Ok(true),
      )
      assert_eq(
        @resources.preparation_capacity_accounting(owner),
        (0L, 0L, 0L, retained, 0L, 0L),
      )
    }
  }
}
