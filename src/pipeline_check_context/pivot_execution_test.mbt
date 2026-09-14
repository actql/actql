///|
test "pivot execution retains empty axes null bucket fill and numeric boundaries" {
  for function in ["count", "min", "max", "first", "sum", "avg"] {
    for
      (keys, columns) in [
        ("[]", "[]"),
        ("[\"id\",\"id\"]", "[]"),
        ("[]", "[\"z\",\"a\"]"),
        ("[\"id\",\"id\"]", "[\"z\",\"a\"]"),
      ] {
      let profiles = resolution_profiles(
        operation_order_fixture(
          "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"sort\":[{\"id\":\"asc\"}]},{\"pivot\":{\"index\":" +
          keys +
          ",\"column\":\"x\",\"values\":" +
          columns +
          ",\"value\":\"id\",\"aggregate\":\"" +
          function +
          "\",\"fill\":{\"$param\":\"n\"}}}]",
        ),
      )
      let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
      let mut partition = 0
      let mut evaluation = 0
      let mut validation = 0
      let mut numeric = 0
      let mut fills = 0
      for i in 0..<operation_resolution_count(index) {
        let site = operation_requirements_at(
          operation_resolution_requirements(index),
          i,
        ).unwrap()
        match operation_resolution_at(index, i).unwrap() {
          Execution(PivotExecution(check)) => {
            assert_true(physical_equal(check.site, site))
            assert_eq(check.input, @pipeline.Step(2))
            assert_true(
              physical_equal(
                @relation.pivot(check.operation).unwrap(),
                check.pivot,
              ),
            )
            assert_eq(
              @relation.pivot_index_count(check.pivot),
              if keys == "[]" {
                0
              } else {
                2
              },
            )
            assert_eq(
              @relation.pivot_column_count(check.pivot),
              if columns == "[]" {
                0
              } else {
                2
              },
            )
            if columns != "[]" {
              assert_eq(@relation.pivot_value_at(check.pivot, 0), Some("z"))
              assert_eq(@relation.pivot_column_at(check.pivot, 0), Some("a"))
            }
            assert_eq(
              operation_execution_phase(PivotExecution(check)),
              BeforeOperationOutput,
            )
            assert_eq(
              operation_execution_failure(PivotExecution(check)),
              RejectOperationOutput,
            )
            match check.rule {
              PartitionPivot => partition += 1
              EvaluatePivot => evaluation += 1
              ValidatePivotResult => validation += 1
              CaptureNumericObservations(_) =>
                fail("numeric observation was resolved without a profile")
            }
          }
          Resolved(Fill(_)) => fills += 1
          Unresolved => {
            // The preceding assertion's consumer linkage is outside this
            // operation-index fixture; inspect every pivot requirement here.
            if site.step != 3 {
              continue
            }
            guard site.requirement is @pipeline.RelationRequirement(pending) &&
              pending.kind is @relation.NumericAggregateObservation else {
              fail("unclosed nonnumeric requirement at step \{site.step}")
            }
            numeric += 1
          }
          _ => ()
        }
      }
      assert_eq((partition, evaluation, validation, fills), (3, 3, 3, 3))
      assert_eq(
        numeric,
        if function == "sum" || function == "avg" {
          3
        } else {
          0
        },
      )
      let work = operation_resolution_work(index)
      assert_true(
        index_program_operation_resolutions(profiles, work, 100) is Ok(_),
      )
      assert_true(
        index_program_operation_resolutions(profiles, work - 1, 100)
        is Err(BudgetExceeded),
      )
    }
  }
}
