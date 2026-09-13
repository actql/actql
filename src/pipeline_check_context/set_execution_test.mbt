///|
test "set semantics retain operands and mandatory physical resource requirements" {
  for op in ["except", "intersect"] {
    for duplicates in ["all", "distinct"] {
      let requirements = operation_order_fixture(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"x\":\"concat($p, to_string($n))\"},\"as\":\"ready\"},{\"" +
        op +
        "\":{\"with\":\"ready\",\"duplicates\":\"" +
        duplicates +
        "\"}}]",
      )
      let profiles = resolution_profiles(requirements)
      let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
      let counts = Array::make(6, 0)
      let mut resources = 0
      for i in 0..<operation_resolution_count(index) {
        let site = operation_requirements_at(requirements, i).unwrap()
        match operation_resolution_at(index, i).unwrap() {
          Execution(SetRows(check)) => {
            assert_true(physical_equal(check.site, site))
            assert_eq(check.left, @pipeline.Step(1))
            assert_eq(check.right, @pipeline.Step(1))
            assert_eq(
              @set.operation(check.operation),
              if op == "except" {
                @set.Except
              } else {
                @set.Intersect
              },
            )
            assert_eq(
              @set.duplicates(check.operation),
              if duplicates == "all" {
                @set.All
              } else {
                @set.Distinct
              },
            )
            assert_eq(
              operation_execution_failure(SetRows(check)),
              RejectOperationOutput,
            )
            let n = match check.rule {
              AdmitBothInputs => 0
              CompareCompleteTypedRows => 1
              PreserveEarliestLeftOccurrences => 2
              BoundOutputByLeftInput => 3
              RetainIdentityAndCompleteness => 4
              RequireComparisonResources => 5
            }
            counts[n] += 1
            assert_eq(
              operation_execution_phase(SetRows(check)),
              if n == 0 || n == 5 {
                BeforeOperationInputUse
              } else {
                BeforeOperationOutput
              },
            )
          }
          Unresolved =>
            if site.requirement
              is @pipeline.SetRequirement(ResolveComparisonResources) {
              resources += 1
            }
          _ => ()
        }
      }
      assert_eq(resources, 0)
      assert_true(counts[0] > 0)
      for n in counts {
        assert_eq(n, counts[0])
      }
      let work = operation_resolution_work(index)
      assert_true(
        index_program_operation_resolutions(profiles, work, 1000) is Ok(_),
      )
      assert_true(
        index_program_operation_resolutions(profiles, work - 1, 1000)
        is Err(BudgetExceeded),
      )
      let count = operation_resolution_count(index)
      assert_true(
        close_program_operations(index, work + count + 1, count)
        is Err(IncompleteResolution(_)),
      )
    }
  }
}
