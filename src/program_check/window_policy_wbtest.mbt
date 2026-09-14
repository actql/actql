///|
test "SourceView windows and window groups retain owned policy and boundary evidence" {
  for events in [false, true] {
    for kind in ["fixed", "sliding"] {
      for
        aggregates in [
          "", "{}", "{\"n\":{\"fn\":\"count\"}}", "{\"n\":{\"fn\":\"min\",\"field\":\"id\"}}",
        ] {
        let window = "{\"kind\":\"" +
          kind +
          "\",\"size\":10,\"step\":3,\"offset\":-1"
        let steps = if events {
          "{\"to_events\":{\"id\":\"id\",\"time\":\"extra\"}},{\"window_events\":" +
          window +
          "}},{\"events\":true}"
        } else {
          "{\"row_window\":" + window + ",\"time\":\"extra\"}}"
        }
        let steps = steps +
          (if aggregates == "" {
            ""
          } else {
            ",{\"window_group\":{\"by\":[\"id\"],\"aggregates\":" +
            aggregates +
            "}}"
          })
        let program = checked_direct_program_fixture(window_steps=steps)
        let pipeline = program.units[0].pipeline
        let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
        assert_eq(publication_policy_source_count(policy), 1)
        assert_eq(
          publication_policy_carrier_step_count(policy),
          if events {
            3
          } else {
            1
          },
        )
        let mut windows = 0
        for i in 0..<publication_policy_carrier_step_count(policy) {
          let retained = publication_policy_carrier_step_at(policy, i).unwrap()
          if retained.operation is Window(operation) {
            windows += 1
            guard @pipeline.step_at(pipeline, retained.step).unwrap().operation
              is Window(original) else {
              fail("window operation lost")
            }
            assert_true(physical_equal(operation, original))
            assert_true(retained.unknown_provenance)
            assert_true(
              @pipeline.window_evidence_at(pipeline, Step(retained.step))
              is Some(_),
            )
          }
        }
        assert_eq(windows, 1)
        assert_eq(unit_window_limit_count(program, 0), Some(1))
        assert_eq(
          publication_policy_group_count(policy),
          if aggregates == "" {
            0
          } else {
            1
          },
        )
        if aggregates != "" {
          let retained = publication_policy_group_at(policy, 0).unwrap()
          guard @pipeline.step_at(pipeline, retained.step).unwrap().operation
            is WindowGroup(original) else {
            fail("window group changed to ordinary group")
          }
          assert_true(physical_equal(original, retained.operation))
          assert_true(
            physical_equal(@relation.group(original).unwrap(), retained.group),
          )
          assert_false(retained.unknown_provenance)
          assert_true(
            @pipeline.window_evidence_at(pipeline, Step(retained.step))
            is Some(_),
          )
          let closure = @context.stage_requirement_operations(
            requirements(program),
          )
          let mut partitions = 0
          for i in 0..<@context.operation_closure_count(closure) {
            if @context.operation_closure_at(closure, i)
              is Some(ExecutionCheck(GroupExecution(check))) &&
              check.rule is PartitionGroups {
              assert_true(physical_equal(check.operation, original))
              assert_true(check.step.operation is WindowGroup(_))
              partitions += 1
            }
          }
          assert_eq(partitions, 1)
        }
      }
    }
  }
}
