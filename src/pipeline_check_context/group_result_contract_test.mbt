///|
test "exact aggregate output contracts close without inventing floating observations" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"group\":{\"by\":[],\"aggregates\":{\"count\":{\"fn\":\"count\"},\"decimal\":{\"fn\":\"sum\",\"expr\":\"CAST('1.00' AS DECIMAL(8,2))\"},\"minimum\":{\"fn\":\"min\",\"field\":\"id\"}}}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
  let closed = close_program_operations(index, 10000000, 100).unwrap()
  let mut contracts = 0
  for i in 0..<operation_closure_count(closed) {
    guard operation_closure_at(closed, i)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is ValidateResultContract(call) else {
      continue
    }
    let result = @relation.aggregate_result(call)
    match @relation.aggregate_name(call) {
      "count" =>
        assert_true(
          @contract.type_equal(
            result,
            @contract.primitive(NumberType, nullable=false),
            1000,
          ),
        )
      "decimal" =>
        assert_true(
          @contract.type_equal(
            result,
            @contract.decimal_contract(38, 2, nullable=true).unwrap(),
            1000,
          ),
        )
      "minimum" =>
        assert_true(
          @contract.type_equal(
            result,
            @contract.primitive(NumberType, nullable=true),
            1000,
          ),
        )
      _ => fail("unexpected aggregate output")
    }
    assert_true(
      physical_equal(
        call,
        @relation.aggregate_for_validation(check.group, check.site.index).unwrap(),
      ),
    )
    assert_eq(
      operation_execution_failure(GroupExecution(check)),
      RejectOperationOutput,
    )
    contracts += 1
  }
  assert_eq(contracts, 9)
  assert_eq(operation_resolution_unresolved_count(index), 0)
}
