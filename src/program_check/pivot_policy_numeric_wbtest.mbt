///|
test "SourceView pivot policy and numeric capture retain the same checked occurrence" {
  for reduction in ["sum", "avg"] {
    let program = checked_direct_program_fixture(
      pivot_body="{\"index\":[\"id\"],\"column\":\"category\",\"values\":[\"2\",\"1\"],\"value\":\"extra\",\"aggregate\":\"" +
        reduction +
        "\"}",
      numeric_profile=Some(numeric_profile_fixture()),
    )
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    let pivot = publication_policy_pivot_at(policy, 0).unwrap()
    assert_true(pivot.unknown_provenance)
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(unit_pivot_numeric_slot_count(program, 0), Some(2))
    for column in 0..<2 {
      let slot = unit_pivot_numeric_slot_at(program, 0, column).unwrap()
      assert_true(
        physical_equal(pivot_numeric_slot_demand(slot).pivot, pivot.pivot),
      )
      assert_eq(pivot_numeric_slot_operation(slot).source_ordinal, pivot.step)
      assert_eq(
        pivot_numeric_slot_operation(slot).unit_definition_cid,
        program.units[0].definition_cid,
      )
    }
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut captures = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(PivotExecution(check))) &&
        check.rule is CaptureNumericObservations(demand) else {
        continue
      }
      captures += 1
      assert_true(physical_equal(check.operation, pivot.operation))
      assert_true(physical_equal(demand.pivot, pivot.pivot))
      assert_eq(
        @context.operation_execution_phase(PivotExecution(check)),
        @context.BeforeOperationOutput,
      )
      assert_eq(
        @context.operation_execution_failure(PivotExecution(check)),
        @context.RejectOperationOutput,
      )
      assert_eq(
        pivot_numeric_slot_count(
          pivot_numeric_slots_for_requirement(program, i).unwrap(),
        ),
        2,
      )
    }
    assert_eq(captures, 1)
  }
}
