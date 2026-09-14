///|
test "owned nest construction links guards depth and both output scopes across imports" {
  for depth in [1, 2] {
    let budget : IdentityBudget = {
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let checked : Array[CheckedProgram] = []
    try {
      let (_, requirements, _, _, units) = local_construction_fixture(
        budget,
        through_check=true,
        checked_results=checked,
        second_stage=true,
        nested_depth=Some(depth),
        producer_expression="id",
        producer_suffix=",{\"nest\":{\"with\":\"derived\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\",\"value\"],\"max_items\":3},\"as\":\"nested\"}",
        producer_result_from="nested",
        extra_step_budget=1,
      )
      assert_eq(depth, 2)
      assert_eq(units.length(), 2)
      assert_eq(checked.length(), 1)
      assert_eq(unit_nest_limit_count(checked[0], 0), Some(1))
      assert_eq(unit_nest_limit_count(checked[0], 1), Some(0))
      let operations = @context.stage_requirement_operations(requirements)
      let mut items = 0
      let mut values = 0
      let mut output = 0
      for i in 0..<@context.operation_closure_count(operations) {
        match @context.operation_closure_at(operations, i) {
          Some(ExecutionCheck(NestItems(limit))) => {
            assert_eq(limit.guard_value, Some(3L))
            assert_eq(limit.maximum, 3L)
            items += 1
          }
          Some(ExecutionCheck(NestValues(check))) => {
            let envelope = check.envelope
            assert_eq(envelope.type_depth, 2)
            assert_eq(envelope.successful_parent_ceiling, 500L)
            assert_eq(envelope.expanded_elements_ceiling, 500L)
            assert_true(
              physical_equal(check.site.pipeline, envelope.items.site.pipeline),
            )
            assert_eq(
              check.site.producer_visit,
              envelope.items.site.producer_visit,
            )
            assert_eq(@context.nest_attachment_field_count(envelope), 1)
            assert_eq(
              @context.nest_attachment_field_at(envelope, 0).unwrap().name,
              @schema.Unqualified("items"),
            )
            values += 1
          }
          Some(ExecutionCheck(NestExecution(check))) =>
            if check.rule is AdmitAttachedValues {
              output += 1
            }
          _ => ()
        }
      }
      assert_eq((items, values, output), (3, 3, 3))
    } catch {
      LocalConstructionFailure::Closure(
        ConstructionFailure::NestValues(@context.DepthExceeded)
      ) => {
        assert_eq(depth, 1)
        assert_eq(checked.length(), 0)
      }
      error => fail("unexpected nest construction failure: \{error}")
    }
  }
}
